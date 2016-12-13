defmodule SSHKit.SSH.Channel do
  defstruct [:connection, :type, :id]

  alias SSHKit.SSH.Channel

  @doc """
  Opens a channel on an SSH connection.

  ## Options

  * `:type` - the type of the channel, defaults to `:session`
  * `:timeout` - defaults to `:infinity`
  * `:initial_window_size` - defaults to 128 KiB
  * `:max_packet_size` - defaults to 32 KiB

  See http://erlang.org/doc/man/ssh_connection.html#session_channel-4
  """
  def open(connection, options \\ []) do
    type = Keyword.get(options, :type, :session)
    timeout = Keyword.get(options, :timeout, :infinity)
    ini_window_size = Keyword.get(options, :initial_window_size, 128 * 1024)
    max_packet_size = Keyword.get(options, :max_packet_size, 32 * 1024)

    case :ssh_connection.session_channel(connection.raw, ini_window_size, max_packet_size, timeout) do
      {:ok, id} -> {:ok, %Channel{connection: connection, type: type, id: id}}
      other -> other
    end
  end

  @doc """
  Closes an SSH channel.

  See http://erlang.org/doc/man/ssh_connection.html#close-2

  Returns `:ok` on success.
  """
  def close(channel) do
    :ssh_connection.close(channel.connection.raw, channel.id)
  end

  @doc """
  Execute a command on the remote host.

  See http://erlang.org/doc/man/ssh_connection.html#exec-4
  """
  def exec(channel, command, timeout \\ :infinity, ini \\ nil, handler) do
    case :ssh_connection.exec(channel.connection.raw, channel.id, command, timeout) do
      :success -> loop(channel, handler, ini, timeout)
      :failure -> {:error, :failure}
      other -> other
    end
  end

  defp loop(channel, fun, state, timeout) do
    connection = channel.connection
    raw = connection.raw
    id = channel.id

    message = receive do
      {:ssh_cm, ^raw, msg} when elem(msg, 1) == id -> Tuple.delete_at(msg, 1)
    after
      timeout -> {:error, :timeout}
    end

    case message do
      {:data, _, data} -> :ssh_connection.adjust_window(raw, id, byte_size(data))
      _ -> :ok
    end

    state = fun.(channel, message, state)

    case message do
      {:closed} -> state
      _ -> loop(channel, fun, state, timeout)
    end
  end
end
