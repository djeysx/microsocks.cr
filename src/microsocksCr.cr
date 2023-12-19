require "./socks.cr"
require "option_parser"

def main
  bind = "::"
  port = 1080
  debug = false

  option_parser = OptionParser.parse do |parser|
    parser.banner = "micro Socks proxy"
    parser.on "-l LISTEN_INTERFACE", "--listen=LISTEN_INTERFACE" do |listen_interface|
      bind = listen_interface
    end
    parser.on "-p LISTEN_PORT", "--port=LISTEN_PORT" do |listen_port|
      port = listen_port.to_i32
    end
    parser.on "-v", "--verbose" do
      debug = true
    end
    parser.on "-h", "--help" do
      puts parser
      exit
    end
  end

  s = Socks::Server.new bind, port, debug
  s.run
end

main
