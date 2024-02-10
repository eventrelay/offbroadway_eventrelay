defmodule Offbroadway.EventRelay.Producer do
  @moduledoc """
  A GenStage producer that continuously receives messages from an EventRelay Subscription/Topic 

  For a quick getting started on using Broadway with EventRelay, please see
  the [EventRelay Guide](https://hexdocs.pm/).

  ## Example
      
      defmodule BE.Broadway do
        use Broadway

        alias Broadway.Message

        def start_link(_opts) do
          Broadway.start_link(__MODULE__,
            name: __MODULE__,
            producer: [
              module:
                {Offbroadway.EventRelay.Producer,
                 subscription_id: "...",
                 host: "localhost",
                 port: "50051",
                 token: "...",
                 certfile: "/path/to/clientcertfile.pem",
                 keyfile: "/path/to/clientkeyfile.pem",
                 cacertfile: "/path/to/cacertfile.pem"},
            ],
            processors: [
              default: [concurrency: 10]
            ]
          )
        end

        def handle_message(_processor_name, message, _context) do
          # Do something with the message/event
          message
        end
      end

  The above configuration will set up a producer that continuously pulls
  events from the configured subscription and sends them downstream.

  ## Options

  #{NimbleOptions.docs(Offbroadway.EventRelay.Options.definition())}

  ### Authentication

  For specifics of how to setup authetication in EventRelay use the 
  [Authentication Guide](https://github.com/eventrelay/eventrelay/wiki/Authentication-and-Authorization) in the EventRelay Wiki.

  See the [Options](#options) section for authentication configuration options.

  ## Acknowledgements

  This producer uses the `PullQueuedEventsRequest` in EventRelay which locks
  an event for a specific subscription when it is pulled from the system. 
  That means any client that pulls events for that subscription in the 
  future will not receive that event.  

  Dealing with failures it is up to the user of this producer to implement 
  your own failure handling via your own acknowledgement handling. 
  See the example below.

  `transformer: {__MODULE__, :transform, []}` in combination with 
  `acknowledger: {__MODULE__, :ack_id, :ack_data}` is what allows you to 
  setup up your own acknowledger.

  In the future EventRelay will support unlocking an event via the [GRPC API](https://github.com/eventrelay/eventrelay/wiki/GRPC) 
  which would allow you to re-enqueue an event for processing again on failure.

  ### Example
      
      defmodule BE.Broadway do
        use Broadway

        alias Broadway.Message

        def start_link(_opts) do
          Broadway.start_link(__MODULE__,
            name: __MODULE__,
            producer: [
              module:
                {Offbroadway.EventRelay.Producer,
                 subscription_id: "...",
                 host: "localhost",
                 port: "50051",
                 token: "...",
                 certfile: "/path/to/clientcertfile.pem",
                 keyfile: "/path/to/clientkeyfile.pem",
                 cacertfile: "/path/to/cacertfile.pem"},
              transformer: {__MODULE__, :transform, []} 
            ],
            processors: [
              default: [concurrency: 10]
            ]
          )
        end

        def transform(message, _opts) do
          %{
            message
            | acknowledger: {__MODULE__, :ack_id, :ack_data}
          }
        end

        def handle_message(_processor_name, message, _context) do
          # Do something with the message/event
          message
        end

        def ack(:ack_id, _successful, _failed) do
          # Handle the failed messages/events here
        end
      end

  """
  use GenStage
  require Logger
  alias Offbroadway.EventRelay.{Options, Client}
  alias Broadway.Message

  def start_link(config) do
    GenStage.start_link(__MODULE__, config)
  end

  @impl true
  def init(opts) do
    Logger.debug("Offbroadway.EventRelay.Producer.init(#{inspect(opts)})")

    {_producer_module, producer_opts} = opts[:broadway][:producer][:module]

    pull_interval = opts[:pull_interval]

    {:ok, channel} = Client.prepare_channel(opts)

    pull_timer = schedule_next_pull(0)

    {:producer,
     %{
       demand: 0,
       channel: channel,
       pull_timer: pull_timer,
       pull_interval: pull_interval,
       pull_task: nil,
       producer_opts: producer_opts
     }}
  end

  def prepare_for_start(_module, broadway_opts) do
    {producer_module, client_opts} = broadway_opts[:producer][:module]

    opts = NimbleOptions.validate!(client_opts, Options.definition())

    broadway_opts =
      put_in(broadway_opts, [:producer, :module], {producer_module, opts})

    Logger.debug("Offbroadway.EventRelay.Producer.prepare_for_start(#{inspect(broadway_opts)}")
    {[], broadway_opts}
  end

  @impl true
  def handle_info(:pull_events, %{pull_timer: nil} = state) do
    Logger.debug("Offbroadway.EventRelay.Producer.handle_info(:pull_events, #{inspect(state)})")
    {:noreply, [], state}
  end

  def handle_info(:pull_events, state) do
    Logger.debug("Offbroadway.EventRelay.Producer.handle_info(:pull_events, #{inspect(state)}")
    handle_pull_events(%{state | pull_timer: nil})
  end

  # This gets called by the Task.async executed in pull_events_from_event_relay
  def handle_info(
        {ref, events},
        %{demand: demand, pull_task: %{ref: ref}} = state
      ) do
    Logger.debug(
      "Offbroadway.EventRelay.Producer.handle_info(#{inspect(events)}, #{inspect(state)})"
    )

    new_demand = demand - length(events)

    pull_timer =
      case {events, new_demand} do
        {[], _} ->
          schedule_next_pull(state.pull_interval)

        {_, 0} ->
          nil

        _ ->
          schedule_next_pull(0)
      end

    {:noreply, events, %{state | demand: new_demand, pull_timer: pull_timer, pull_task: nil}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.info("Offbroadway.EventRelay.Producer.handle_info(#{inspect(msg)}, #{inspect(state)})")
    {:noreply, [], state}
  end

  @impl true
  def handle_demand(incoming_demand, %{demand: demand} = state) do
    handle_pull_events(%{state | demand: demand + incoming_demand})
  end

  defp handle_pull_events(%{pull_timer: nil, demand: demand, pull_task: nil} = state)
       when demand > 0 do
    task = pull_events_from_event_relay(state, demand)

    {:noreply, [], %{state | pull_task: task}}
  end

  defp handle_pull_events(state) do
    {:noreply, [], state}
  end

  defp pull_events_from_event_relay(state, total_demand) do
    Logger.debug(
      "Offbroadway.EventRelay.Producer.pull_events_from_event_relay(#{inspect(state)}, #{inspect(total_demand)})"
    )

    %{channel: channel, producer_opts: producer_opts} = state
    subscription_id = producer_opts[:subscription_id]

    Task.async(fn ->
      channel
      |> Client.pull_queued_events(subscription_id, total_demand)
      |> handle_pull_queued_events()
    end)
  end

  def schedule_next_pull(pull_interval) do
    Logger.debug("Offbroadway.EventRelay.Producer.schedule_next_pull(#{inspect(pull_interval)})")
    Process.send_after(self(), :pull_events, pull_interval)
  end

  def handle_pull_queued_events({:ok, result}) do
    Enum.map(result.events, fn event ->
      %Message{
        data: event,
        acknowledger: Broadway.NoopAcknowledger.init()
      }
    end)
  end

  def handle_pull_queued_events(error) do
    Logger.error(
      "Offbroadway.EventRelay.Producer.pull_events_from_event_relay error=#{inspect(error)}"
    )

    []
  end
end
