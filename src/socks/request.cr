class Socks::Request
  # Commands
  ConnectCommand   = 1_u8
  BindCommand      = 2_u8
  AssociateCommand = 3_u8

  # Address types
  IPV4 = 1
  FQDN = 3
  IPV6 = 4

  # IO
  COPY_BUFFER_SIZE = 8192

  enum ResponseCode : UInt8
    SUCCESS
    FAILURE
    RULE_FAILURE
    NETWORK_UNREACHABLE
    HOST_UNREACHABLE
    CONNECTION_REFUSED
    TTL_EXPIRED
    COMMAND_NOT_SUPPORTED
    ADDR_TYPE_NOT_SUPPORTED
  end

  @command : UInt8
  @addr_type = 0_u8
  @port = 0_u16
  @fqdn = ""
  @ipv4 = StaticArray(UInt8, 4).new { 0_u8 }
  @ipv6 = StaticArray(UInt8, 16).new { 0_u8 }

  def initialize(@client : TCPSocket, @id_msg : String, @debug : Bool = false)
    buf = uninitialized UInt8[3]
    @client.read_fully?(buf.to_slice) || raise Socks::Error.new("Failed to get command version")
    buf[0] == Socks::VERSION || raise Socks::Error.new("Unsupported command version #{buf[0]}")

    @command = buf[1]
    unless read_addr_spec
      send_reply(ResponseCode::ADDR_TYPE_NOT_SUPPORTED)
      raise Socks::Error.new("Address type not supported #{@addr_type}")
    end
  end

  def read_addr_spec
    @addr_type = @client.read_byte || raise Socks::Error.new("Failed to get command addr_type")
    # @addr_type = addr_type

    case @addr_type
    when IPV4
      @client.read_fully?(@ipv4.to_slice) || raise Socks::Error.new("Failed to get ipv4 address")
    when IPV6
      @client.read_fully?(@ipv6.to_slice) || raise Socks::Error.new("Failed to get ipv6 address")
    when FQDN
      len = @client.read_byte
      len || raise Socks::Error.new("Failed to get FQDN length")
      len = len.to_i

      buf = uninitialized UInt8[256]
      slice = Slice.new(buf.to_unsafe, len)
      @client.read_fully?(slice) || raise Socks::Error.new("Failed to get FQDN")
      @fqdn = String.new(slice)
    else
      return false
    end

    buf2 = uninitialized UInt8[2]
    @client.read_fully?(buf2.to_slice) || raise Socks::Error.new("Failed to get port")

    @port = buf2[0].to_u16 << 8 | buf2[1].to_u16

    true
  end

  def send_reply(resp : ResponseCode)
    to = @client
    to.write_byte(Socks::VERSION)
    to.write_byte(resp.value.to_u8)
    to.write_byte(0_u8) # reserved
    to.write_byte(@addr_type)

    case @addr_type
    when IPV4
      to.write(@ipv4.to_slice)
    when IPV6
      to.write(@ipv6.to_slice)
    when FQDN
      to.write_byte(@fqdn.bytesize.to_u8)
      to.write(@fqdn.to_slice)
    else
      4.times { to.write_byte(0_u8) }
    end

    to.write_byte((@port >> 8).to_u8)
    to.write_byte((@port & 0xFF).to_u8)
  rescue ex
    raise Socks::Error.new("Failed to send reply #{ex.message}")
  end

  def handle
    case @command
    when ConnectCommand
      handle_connect
    when BindCommand
      handle_bind
    when AssociateCommand
      handle_associate
    else
      send_reply(ResponseCode::COMMAND_NOT_SUPPORTED)
      raise Socks::Error.new("Unsupported command: #{@command}")
    end
  end

  def handle_connect
    addr = case @addr_type
           when IPV4
             "#{@ipv4[0]}.#{@ipv4[1]}.#{@ipv4[2]}.#{@ipv4[3]}"
           when IPV6
             String.build do |io|
               io << @ipv6[0].to_s(16, precision: 2)
               io << @ipv6[1].to_s(16, precision: 2)
               io << ":"
               io << @ipv6[2].to_s(16, precision: 2)
               io << @ipv6[3].to_s(16, precision: 2)
               io << ":"
               io << @ipv6[4].to_s(16, precision: 2)
               io << @ipv6[5].to_s(16, precision: 2)
               io << ":"
               io << @ipv6[6].to_s(16, precision: 2)
               io << @ipv6[7].to_s(16, precision: 2)
               io << ":"
               io << @ipv6[8].to_s(16, precision: 2)
               io << @ipv6[9].to_s(16, precision: 2)
               io << ":"
               io << @ipv6[10].to_s(16, precision: 2)
               io << @ipv6[11].to_s(16, precision: 2)
               io << ":"
               io << @ipv6[12].to_s(16, precision: 2)
               io << @ipv6[13].to_s(16, precision: 2)
               io << ":"
               io << @ipv6[14].to_s(16, precision: 2)
               io << @ipv6[15].to_s(16, precision: 2)
             end
           when FQDN
             @fqdn
           else
             send_reply(ResponseCode::ADDR_TYPE_NOT_SUPPORTED)
             raise Socks::Error.new("Not supported addr_type #{@addr_type}")
           end

    # NETWORK_UNREACHABLE
    # HOST_UNREACHABLE
    # CONNECTION_REFUSED
    # TTL_EXPIRED
    puts("#{@id_msg} addr_type:#{@addr_type} addr:#{addr}") if @debug

    sock = begin
      TCPSocket.new(addr, @port, dns_timeout: 10.seconds, connect_timeout: 10.seconds)
    rescue IO::TimeoutError
      send_reply(ResponseCode::TTL_EXPIRED)
      raise Socks::Error.new("IO timeout to connect to host")
    rescue Socket::Error
      send_reply(ResponseCode::CONNECTION_REFUSED)
      raise Socks::Error.new("Connection refused")
    end

    sock.read_timeout = 180.seconds

    send_reply(ResponseCode::SUCCESS)

    ch = Channel(Nil).new(2)
    spawn copy_io(sock, @client, ch)
    spawn copy_io(@client, sock, ch)

    ch.receive
    ch.receive
  ensure
    @client.close
    sock.try &.close
  end

  private def copy_io(src, dst, ch)
    copy(src, dst)
  rescue IO::Error
  rescue Socket::Error
  rescue IO::TimeoutError
  ensure
    src.close
    dst.close
    ch.send(nil)
  end

  # Copy of IO.copy with modified buffer size
  private def copy(src, dst) : Int64
    buffer = uninitialized UInt8[COPY_BUFFER_SIZE]
    count = 0_i64
    while (len = src.read(buffer.to_slice).to_i32) > 0
      dst.write buffer.to_slice[0, len]
      count &+= len
    end
    count
  end

  def handle_bind
    send_reply(ResponseCode::COMMAND_NOT_SUPPORTED)
  end

  def handle_associate
    send_reply(ResponseCode::COMMAND_NOT_SUPPORTED)
  end
end
