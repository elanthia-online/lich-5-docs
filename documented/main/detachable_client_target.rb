# frozen_string_literal: true

module Lich
  module Main
    # Parses the value of +--detachable-client=VALUE+ (and the +--headless+
    # alias) into a bind host token and a port, without touching the network.
    # Keyword hosts (tailscale/lan/any) are resolved to concrete addresses
    # later by Lich::Common::BindHostResolver.
    #
    # Accepted forms: +PORT+, +auto+, +HOST:PORT+, +HOST:auto+, +[IPV6]:PORT+
    #
    # @since 5.18.0
    module DetachableClientTarget
      # Raised when the flag value does not match any accepted form.
      ParseError = Class.new(ArgumentError)

      # +host+ is nil when only a port was given (the bind host then comes
      # from --bind-address or the loopback default); +port+ 0 means the OS
      # assigns one.
      Target = Struct.new(:host, :port, keyword_init: true)

      USAGE = '--detachable-client requires PORT, auto, or HOST:PORT ' \
              '(HOST may be tailscale, lan, any, an IP address, or a hostname)'

      # Parses a flag value into a Target.
      #
      # @param value [String] text after the = in --detachable-client=VALUE
      # @return [Target]
      # @raise [ParseError] when the value matches no accepted form
      def self.parse(value)
        token = value.to_s.strip
        raise ParseError, USAGE if token.empty?
        return Target.new(host: nil, port: 0) if token.casecmp('auto').zero?
        return Target.new(host: nil, port: parse_port(token)) if token.match?(/\A\d+\z/)

        host, port_token = split_host_port(token)
        port = port_token.casecmp('auto').zero? ? 0 : parse_port(port_token)
        Target.new(host: host, port: port)
      end

      # Splits a HOST:PORT token into its components, handling bracketed IPv6 addresses.
      #
      # Accepts plain HOST:PORT or [IPV6]:PORT forms. The method does not validate the host
      # or port values—it merely extracts them as strings.
      #
      # @param token [String] a HOST:PORT or [IPV6]:PORT string
      # @return [Array<String>] a two-element array [host, port_token]
      # @raise [ParseError] when the token does not match either accepted form
      # @example Split plain host:port
      #   split_host_port("example.com:8080") #=> ["example.com", "8080"]
      # @example Split bracketed IPv6 address
      #   split_host_port("[::1]:9000") #=> ["::1", "9000"]
      # @api private
      def self.split_host_port(token)
        if (bracketed = token.match(/\A\[([^\]]+)\]:([^:]+)\z/))
          bracketed.captures
        elsif (plain = token.match(/\A([^:]+):([^:]+)\z/))
          plain.captures
        else
          raise ParseError, USAGE
        end
      end

      # Converts a port string to an integer and validates it is in the range 0–65535.
      #
      # Port 0 is accepted and signals that the operating system should assign an available port.
      #
      # @param port_token [String] a decimal port number (e.g., "8080", "0")
      # @return [Integer] the port number, guaranteed to be in range 0–65535
      # @raise [ParseError] when the token cannot be parsed as an integer or is outside the valid range
      # @example
      #   parse_port("8080") #=> 8080
      # @api private
      def self.parse_port(port_token)
        port = begin
          Integer(port_token, 10)
        rescue ArgumentError, TypeError
          raise ParseError, USAGE
        end
        unless port.between?(0, 65_535)
          raise ParseError, 'detachable client port must be between 0 and 65535 (0 or auto lets the OS choose)'
        end
        port
      end
    end
  end
end
