defmodule Offbroadway.EventRelay.Client do
  @moduledoc """
  Module to interact with EventRelay
  """
  alias ERWeb.Grpc.Eventrelay.Events.Stub

  require Logger

  def prepare_channel(opts) do
    host = opts[:host]
    port = opts[:port]
    token = opts[:token]
    cacertfile = opts[:cacertfile]
    certfile = opts[:certfile]
    keyfile = opts[:keyfile]

    grpc_opts = []

    grpc_opts =
      if cacertfile && certfile && keyfile do
        cred =
          GRPC.Credential.new(
            ssl: [
              verify: :verify_peer,
              cacertfile: cacertfile,
              keyfile: keyfile,
              certfile: certfile
            ]
          )

        Keyword.merge(grpc_opts, cred: cred)
      else
        grpc_opts
      end

    grpc_opts =
      if token do
        Keyword.put(grpc_opts, :headers, [
          {"authorization", "Bearer #{token}"}
        ])
      else
        grpc_opts
      end

    GRPC.Stub.connect("#{host}:#{port}", grpc_opts)
  end

  def pull_queued_events(channel, destination_id, batch_size) do
    request = %ERWeb.Grpc.Eventrelay.PullQueuedEventsRequest{
      destination_id: destination_id,
      batch_size: batch_size
    }

    Stub.pull_queued_events(channel, request)
  end
end
