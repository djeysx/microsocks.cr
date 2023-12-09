require "./socks.cr"

def main
    p :started
    s = Socks::Server.new "0.0.0.0", (ARGV[0]? || 8088).to_i, true
    s.run
  end
  
main
  