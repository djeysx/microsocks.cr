require "socket"

class Socks::Server
  def initialize(@listen_host : String, @listen_port : Int32, @debug : Bool = true)
    @server = TCPServer.new @listen_host, @listen_port, 64, 10, true
  end

  def stop!
    @server.close
  end

  def run
    loop do
      spawn handle(@server.accept)
    end
  end

  def auth(client)
    # Actually just skip it

    num_methods = client.read_byte
    num_methods || raise Error.new("Failed to get number of methods")

    num_methods.times do
      method = client.read_byte
      method || raise Error.new("Failed to get auth method")
    end

    begin
      client.write_byte(Socks::VERSION)
      client.write_byte(0_u8)
    rescue ex
      raise Socks::Error.new("Failed to write auth reply `#{ex.inspect}`")
    end

    nil
  end

  def handle(client)
    id_msg = "[SOCKS-#{client.remote_address}]"

    version = client.read_byte
    version || raise Error.new("Failed to get version byte")
    version == Socks::VERSION || raise Error.new("Unsupported SOCKS version #{version}")

    auth = auth(client)

    request = Request.new(client, auth)
    request.handle

    STDERR.puts("#{id_msg} OK") if @debug
  rescue ex : Socks::Error
    STDERR.puts("#{id_msg} ERR: #{ex.message}") if @debug
  ensure
    client.close
  end
end
