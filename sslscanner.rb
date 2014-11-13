#!/usr/bin/env ruby

require 'getoptlong'
require 'openssl'
require 'socket'

USAGE = "Usage: #{File.basename($0)}: [-s <server hostname/ip>] [-p <port>] [-d <debug>] [-c <certificate information>]"

# SSL Scanner by Bar Hofesh (bararchy) bar.hofesh@gmail.com

class Scanner
    NO_SSLV2   = 16777216
    NO_SSLV3   = 33554432
    NO_TLSV1   = 67108864
    NO_TLSV1_1 = 268435456
    NO_TLSV1_2 = 134217728

    SSLV2      = NO_SSLV3 + NO_TLSV1 + NO_TLSV1_1 + NO_TLSV1_2
    SSLV3      = NO_SSLV2 + NO_TLSV1 + NO_TLSV1_1 + NO_TLSV1_2
    TLSV1      = NO_SSLV2 + NO_SSLV3 + NO_TLSV1_1 + NO_TLSV1_2
    TLSV1_1    = NO_SSLV2 + NO_SSLV3 + NO_TLSV1   + NO_TLSV1_2
    TLSV1_2    = NO_SSLV2 + NO_SSLV3 + NO_TLSV1   + NO_TLSV1_1

    PROTOCOLS  = [SSLV2, SSLV3, TLSV1, TLSV1_1, TLSV1_2]
    CIPHERS    = 'ALL::HIGH::MEDIUM::LOW::SSL23'


  def ssl_scan

    # Index by color
    puts "\e[0;32mstrong\033[0m -- \e[0;33mweak\033[0m -- \033[1;31mvulnerable\033[0m\r\n\r\n"

    if @check_cert == true
      puts get_certificate_information
    end

    scan
  end

  def scan
    p = 0
    c = []
    begin
      PROTOCOLS.each do |protocol|
        p = protocol
        ssl_context = OpenSSL::SSL::SSLContext.new
        ssl_context.ciphers = CIPHERS
        ssl_context.options = protocol

        ssl_context.ciphers.each do |cipher|
          c = cipher
          sleep 0
          ssl_context = OpenSSL::SSL::SSLContext.new
          ssl_context.options = protocol
          ssl_context.ciphers = cipher[0].to_s
          begin
            tcp_socket = TCPSocket.new("#{@server}", @port)
          rescue => e
            puts e.message
            exit 1
          end

          socket_destination = OpenSSL::SSL::SSLSocket.new tcp_socket, ssl_context
          socket_destination.connect

          if protocol == @SSLv3
            puts parse(cipher[0].to_s, cipher[3], protocol)
          else
            puts parse(cipher[0].to_s, cipher[2], protocol)
          end

          socket_destination.close if socket_destination
        end
      end
    rescue => e
      if @debug
        puts e.message
        puts e.backtrace.join "\n"
        case p
        when SSLV2
          puts "Server Don't Supports: SSLv2 #{c[0]} #{c[2]} bits"
        when SSLV3
          puts "Server Don't Supports: SSLv3 #{c[0]} #{c[3]} bits"
        when TLSV1
          puts "Server Don't Supports: TLSv1 #{c[0]} #{c[2]} bits"
        when TLSV1_1
          puts "Server Don't Supports: TLSv1.1 #{c[0]} #{c[2]} bits"
        when TLSV1_2
          puts "Server Don't Supports: TLSv1.2 #{c[0]} #{c[2]} bits"
        end
      end
    end
  end

  def get_certificate_information
    ssl_context = OpenSSL::SSL::SSLContext.new
    cert_store = OpenSSL::X509::Store.new
    cert_store.set_default_paths
    ssl_context.cert_store = cert_store

    tcp_socket = TCPSocket.new("#{@server}", @port.to_i)
    socket_destination = OpenSSL::SSL::SSLSocket.new tcp_socket, ssl_context
    socket_destination.connect

    cert = OpenSSL::X509::Certificate.new(socket_destination.peer_cert)
    certprops = OpenSSL::X509::Name.new(cert.issuer).to_a

    issuer = certprops.select { |name, data, type| name == "O" }.first[1]

    results = ["\r\n\033[1m== Certificate Information ==\033[0m",
               "valid: #{(socket_destination.verify_result == 0)}",
               "valid from: #{cert.not_before}",
               "valid until: #{cert.not_after}",
               "issuer: #{issuer}",
               "subject: #{cert.subject}",
               "public key:\r\n#{cert.public_key}"].join("\r\n")	
    results
  rescue
  ensure
    socket_destination.close if socket_destination
    tcp_socket.close         if tcp_socket
  end


  def parse(cipher_name, cipher_bits, protocol)
    if protocol == @SSLv2
      ssl_version = "\033[1;31mSSLv2\033[0m"
    elsif protocol == @SSLv3
      ssl_version = "\e[0;33mSSLv3\033[0m"
    elsif protocol == @TLSv1
      ssl_version = "\033[1mTLSv1\033[0m"
    elsif protocol == @TLSv1_1
      ssl_version = "\033[1mTLSv1.1\033[0m"
    elsif protocol == @TLSv1_2
      ssl_version = "\033[1mTLSv1.2\033[0m"
    end

    if cipher_name.match(/RC4/i)
      cipher = "\e[0;33m#{cipher_name}\033[0m"
    elsif cipher_name.match(/RC2/i)
      cipher = "\033[1;31m#{cipher_name}\033[0m"
    elsif cipher_name.match(/MD5/i)
      cipher = "\e[0;33m#{cipher_name}\033[0m"
    else
      cipher = "\e[0;32m#{cipher_name}\033[0m"
    end

    if cipher_bits == 40
      bits = "\033[1;31m#{cipher_bits}\033[0m"
    elsif cipher_bits == 56
      bits = "\033[1;31m#{cipher_bits}\033[0m"
    else
      bits = "\e[0;32m#{cipher_bits}\033[0m"
    end
    if protocol == @SSLv3 && cipher_name.match(/RC/i).to_s == ""
      return "Server Supports #{ssl_version} #{cipher} #{bits} \033[1;31m -- POODLE (CVE-2014-3566)\033[0m"
    else
      return "Server Supports #{ssl_version} #{cipher} #{bits}"
    end
  end

  def initialize(options = {})
    @server     = options[:server]
    @port       = options[:port]
    @debug      = options[:debug]
    @check_cert = options[:check_cert]
  end
end


opts = GetoptLong.new(
  ['-s', GetoptLong::REQUIRED_ARGUMENT],
  ['-p', GetoptLong::REQUIRED_ARGUMENT],
  ['-d', GetoptLong::NO_ARGUMENT],
  ['-c', GetoptLong::NO_ARGUMENT]
)

options = {debug: false, check_cert: false}

opts.each do |opt, arg|
  case opt
  when '-s'
    options[:server] = arg
  when '-p'
    options[:port] = arg.to_i
  when '-d'
    options[:debug] = true
  when 'c'
    options[:check_cert] = true
  end
end

if options.keys.length <= 2
  p ARGV
  p options
  puts USAGE
  exit 0
end

if options[:server].empty? || options[:port] == 0
  $stderr.puts 'Missing required fields'
  puts USAGE
  exit 0
end

trap("INT") do
  puts "Exiting..."
  exit
end

scanner = Scanner.new(options)
scanner.ssl_scan
