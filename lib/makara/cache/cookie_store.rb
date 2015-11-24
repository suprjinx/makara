module Makara
  module Cache
    class CookieStore

      def read(key)
        cache[key]
      end

      def write(key, value, options = {})
        cache[key] = value
        true
      end

      private

      def cache
        Thread.current[Makara::Middleware::CACHE_IDENTIFIER] ||= {}
      end

    end
  end
end