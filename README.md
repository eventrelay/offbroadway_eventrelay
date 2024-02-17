# Offbroadway EventRelay Producer

This producer allows you to stream events from EventRelay and process them using Broadway. It still needs 
some tender loving care to get it to a place where you could use it in production. So use with caution. 

**A lot of inspiration, code, and documentation have been borrowed from the [Google Cloud Pub/Sub Producer](https://github.com/dashbitco/broadway_cloud_pub_sub)**

## Installation

If [available in Hex](https://hex.pm/packages/offbroadway_eventrelay), the package can be installed
by adding `offbroadway_eventrelay` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:offbroadway_eventrelay, "~> 0.2.0"}
  ]
end
```

## Guide

EventRelay is a self-hosted real-time event streaming application. This guide assumes
that you have EventRelay installed locally and that it can be accessed on localhost.

## Getting Started

In order to use Broadway with EventRelay you need to:

  1. [Install](https://github.com/eventrelay/eventrelay/wiki/Getting-Started) EventRelay
  1. Configure your Elixir project to use Broadway
  1. Define your pipeline configuration
  1. Implement Broadway callbacks
  1. Run the Broadway pipeline
  1. Tune the configuration (Optional)

If you are just getting familiar with EventRelay, refer to [the wiki](https://github.com/eventrelay/eventrelay/wiki)
to get started. 

If you have an existing EventRelay instance, topic, destination, and API Key, you can skip [step
1](#configure-eventrelay) and jump to [Start a new project](#starting-a-new-project)
section.

## Configure EventRelay

You will first need a running instance of EventRelay. If you don't have one see the 
[Getting Started](https://github.com/eventrelay/eventrelay/wiki/Getting-Started) guide.

Login to EventRelay's web [UI](http://localhost:9000/users/log_in)

The login credentials can be found in the [seeds file](https://github.com/eventrelay/eventrelay/blob/main/priv/repo/seeds.exs#L24).

    email: "user@example.com"
    password: "password123!@"

Create a new topic:

Name: users

Create a new destination:

Name: Users Stream
Type: api
Topic: users

You will need the destination ID later to configure the Broadway Producer.

Create an API Key:

Name: Broadway Producer
Status: active
Type: consumer
TLS Hostname: localhost 

You will need to the token, TLS certificate and key files that are generated for the API Key
later to configure the Broadway Producer.

### Starting a new project

If you plan to start a new project, just run:

    $ mix new my_app --sup

The `--sup` flag instructs Elixir to generate an application with a supervision tree.

### Setting up dependencies

Add `:offbroadway_eventrelay` to the list of dependencies in `mix.exs`

    defp deps() do
      [
        ...
        {:offbroadway_eventrelay, "~> 0.2"},
      ]
    end

Don't forget to check for the latest version of dependencies.

## Define the pipeline configuration

Broadway is a process-based behaviour and to define a Broadway pipeline, we need to define three
functions: `start_link/1`, `handle_message/3` and `handle_batch/4`. We will cover `start_link/1`
in this section and the `handle_` callbacks in the next one.

Similar to other process-based behaviour, `start_link/1` simply delegates to
`Broadway.start_link/2`, which should define the producers, processors, and batchers in the
Broadway pipeline. 

    defmodule MyBroadway do
      use Broadway

      alias Broadway.Message

      def start_link(_opts) do
        Broadway.start_link(__MODULE__,
          name: __MODULE__,
          producer: [
            module:
              {Offbroadway.EventRelay.Producer,
               destination_id: "{destination_id}",
               host: "localhost",
               port: "50051",
               token: "{token}", # Part of API Key
               certfile: "/path/to/api_key_certfile.pem", # Part of API Key
               keyfile: "/path/to/api_key_keyfile.pem", # Part of API Key
               cacertfile: "/path/to/cacertfile.pem"} # From initial EventRelay installation
          ],
          processors: [
            default: []
          ],
          batchers: [
            default: [
              batch_size: 10,
              batch_timeout: 2_000
            ]
          ]
        )
      end

      ...callbacks...
    end

For a full list of options for `Offbroadway.EventRelay.Producer`, please see [the
documentation](https://hexdocs.pm/offbroadway_eventrelay).

For general information about setting up Broadway, see `Broadway` module docs as well as
`Broadway.start_link/2`.

## Implement Broadway callbacks

In order to process incoming messages, we need to implement the required callbacks. For the sake
of simplicity, we're considering that all messages received from the queue are strings and our
processor calls `String.upcase/1` on them:

    defmodule MyBroadway do
      use Broadway

      alias Broadway.Message

      ...start_link...

      def handle_message(_, %Message{data: data} = message, _) do
        message
        |> Message.update_data(fn data -> 
            first_name = get_in(data, ["person", "first_name"])
            String.upcase(to_string(first_name)) 
           end)
      end

      def handle_batch(_, messages, _, _) do
        list = messages |> Enum.map(fn e -> e.data end)
        IO.inspect(list, label: "Got batch of finished jobs from processors.")
        messages
      end
    end

We are not doing anything fancy here, but it should be enough for our purpose. First we update the
message's data individually inside `handle_message/3` and then we print each batch inside
`handle_batch/4`.

For more information, see `c:Broadway.handle_message/3` and `c:Broadway.handle_batch/4`.

## Run the Broadway pipeline

To run your `Broadway` pipeline, you need to add it as a child in a supervision tree. Most
applications have a supervision tree def2ned at `lib/my_app/application.ex`. You can add Broadway
as a child to a supervisor as follows:

    children = [
      {MyBroadway, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)

Now the Broadway pipeline should be started when your application starts. Also, if your Broadway
pipeline has any dependency (for example, it needs to talk to the database), make sure that
it is listed *after* its dependencies in the supervision tree.

If you followed the previous section about configuring EventRelay, you can now test the
the pipeline. In one terminal tab start the application:

    $ iex -S mix

And in another tab, send a couple of test events to EventRelay:

    $ grpcurl -H "Authorization: Bearer {token}" -key /path/to/api_key_keyfile.pem -cert /path/to/api_key_certfile.pem -cacert /path/to/cacertfile.pem -proto event_relay.proto -d '{"topic": "users", "durable": true, "events": [{"name": "user.created", "data": "{\"person\": {\"first_name\": \"Bill\", \"last_name\": \"Roberts\", \"twitter_url\": \"https://twitter.com/billroberts\", \"uuid\": \"6131e043-52eb-4112-82f0-2817149b0e22\"}}", "source": "MyApp", "context": {"ip_address": "127.0.0.1"}}]}' localhost:50051 eventrelay.Events.PublishEvents

    $ grpcurl -H "Authorization: Bearer {token}" -key /path/to/api_key_keyfile.pem -cert /path/to/api_key_certfile.pem -cacert /path/to/cacertfile.pem -proto event_relay.proto -d '{"topic": "users", "durable": true, "events": [{"name": "user.created", "data": "{\"person\": {\"first_name\": \"Betty\", \"last_name\": \"Roberts\", \"twitter_url\": \"https://twitter.com/bettyroberts\", \"uuid\": \"6131e043-52eb-4112-82f0-2817149b0e22\"}}", "source": "MyApp", "context": {"ip_address": "127.0.0.1"}}]}' localhost:50051 eventrelay.Events.PublishEvents


Now, In the first tab, you should see output similar to:

```
Got batch of finished jobs from processors.: ["BILL", "BETTY"]
```

## Tuning the configuration

Some of the configuration options available for Broadway come already with a
"reasonable" default value. However those values might not suit your
requirements. Depending on the number of messages you get, how much processing
they need and how much IO work is going to take place, you might need completely
different values to optimize the flow of your pipeline. The `concurrency` option
available for every set of producers, processors and batchers, among with
`max_demand`, `batch_size`, and `batch_timeout` can give you a great deal
of flexibility.

The `concurrency` option controls the concurrency level in each layer of
the pipeline.
See the notes on [`Producer concurrency`](https://hexdocs.pm/broadway/Broadway.html#module-producer-concurrency)
and [`Batcher concurrency`](https://hexdocs.pm/broadway/Broadway.html#module-batcher-concurrency)
for details.

Here's an example on how you could tune them according to
your needs.

    defmodule MyBroadway do
      use Broadway

      def start_link(_opts) do
        Broadway.start_link(__MODULE__,
          name: __MODULE__,
          producer: [
            ...
            concurrency: 10,
          ],
          processors: [
            default: [
              concurrency: 100,
              max_demand: 1,
            ]
          ],
          batchers: [
            default: [
              batch_size: 10,
              concurrency: 10,
            ]
          ]
        )
      end

      ...callbacks...
    end

In order to get a good set of configurations for your pipeline, it's
important to respect the limitations of the servers you're running,
as well as the limitations of the services you're providing/consuming
data to/from. Broadway comes with telemetry, so you can measure your
pipeline and help ensure your changes are effective.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). The docs can
be found at <https://hexdocs.pm/offbroadway_eventrelay>.

