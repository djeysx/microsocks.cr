require "socket"

class Socks::Server
  def initialize(@listen_host : String = "::", @listen_port : Int32 = 1080, @debug : Bool = true)
    @server = TCPServer.new @listen_host, @listen_port, 32
  end

  def stop!
    @server.close
  end

  def run
    puts "Listening on #{@listen_host}:#{@listen_port}" if @debug
    loop do
      spawn handle(@server.accept)
    end
  end

  def auth(client)
    # Actually just skip it
    # Only X'00' NO AUTHENTICATION REQUIRED

    num_methods = client.read_byte || raise Error.new("Failed to get number of methods")

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
    puts("#{id_msg} Accept") if @debug

    version = client.read_byte || raise Error.new("Failed to get version byte")
    version == Socks::VERSION || raise Error.new("Unsupported SOCKS version #{version}")

    auth(client)

    request = Request.new(client, id_msg, @debug)
    request.handle

    puts("#{id_msg} Close OK") if @debug
  rescue ex : Socks::Error
    puts("#{id_msg} Close ERR: #{ex.message}") if @debug
  ensure
    client.close
  end
end
