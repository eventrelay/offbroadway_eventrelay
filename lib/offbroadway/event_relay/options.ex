defmodule Offbroadway.EventRelay.Options do
  @moduledoc false

  @default_max_number_of_events 50

  @default_pull_interval 5_000

  @default_pull_timeout :infinity

  definition = [
    # Handled by Broadway.
    broadway: [type: :any, doc: false],
    subscription_id: [
      type: {:custom, __MODULE__, :type_non_empty_string, [[{:name, :subscription_id}]]},
      required: true,
      doc: """
      The name of the subscription, including the project.
      For example, if you project is named `"my-project"` and your
      subscription is named `"my-subscription"`, then your subscription
      name is `"projects/my-project/subscriptions/my-subscription"`.
      """
    ],
    host: [
      type: {:custom, __MODULE__, :type_non_empty_string, [[{:name, :host}]]},
      required: true,
      default: :noop,
      doc: """
      The host for EventRelay 
      """
    ],
    port: [
      type: {:custom, __MODULE__, :type_non_empty_string, [[{:name, :port}]]},
      required: true,
      default: :noop,
      doc: """
      The port for the GRPC API for EventRelay
      """
    ],
    token: [
      type: {:custom, __MODULE__, :type_non_empty_string, [[{:name, :token}]]},
      required: false,
      doc: """
      An ApiKey token that has access to the EventRelay Subscription
      """
    ],
    cacertfile: [
      type: {:custom, __MODULE__, :type_non_empty_string, [[{:name, :cacertfile}]]},
      required: false,
      doc: """
      Path to a PEM formatted CA certificate file
      """
    ],
    certfile: [
      type: {:custom, __MODULE__, :type_non_empty_string, [[{:name, :certfile}]]},
      required: false,
      doc: """
      Path to a PEM formatted client certificate file
      """
    ],
    keyfile: [
      type: {:custom, __MODULE__, :type_non_empty_string, [[{:name, :keyfile}]]},
      required: false,
      doc: """
      Path to a PEM formatted client key file
      """
    ],
    max_number_of_events: [
      doc: "The maximum number of events to be fetched per request.",
      type: :pos_integer,
      default: @default_max_number_of_events
    ],
    pull_interval: [
      type: :integer,
      default: @default_pull_interval,
      doc: """
      The duration (in milliseconds) for which the producer waits
      before making a request for more messages.
      """
    ],
    pull_timeout: [
      type: {:custom, __MODULE__, :type_positive_integer_or_infinity, [[{:name, :pull_timeout}]]},
      default: @default_pull_timeout,
      doc: """
      The maximum time (in milliseconds) to wait for a response
      before the pull client returns an error.
      """
    ]
  ]

  @definition NimbleOptions.new!(definition)

  def definition do
    @definition
  end

  def type_non_empty_string("", [{:name, name}]) do
    {:error, "expected :#{name} to be a non-empty string, got: \"\""}
  end

  def type_non_empty_string(value, _)
      when not is_nil(value) and is_binary(value) do
    {:ok, value}
  end

  def type_non_empty_string(value, [{:name, name}]) do
    {:error, "expected :#{name} to be a non-empty string, got: #{inspect(value)}"}
  end

  def type_positive_integer_or_infinity(value, _) when is_integer(value) and value > 0 do
    {:ok, value}
  end

  def type_positive_integer_or_infinity(:infinity, _) do
    {:ok, :infinity}
  end

  def type_positive_integer_or_infinity(value, [{:name, name}]) do
    {:error, "expected :#{name} to be a positive integer or :infinity, got: #{inspect(value)}"}
  end
end
