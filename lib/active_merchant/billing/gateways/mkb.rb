module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class MkbGateway < Gateway

      self.display_name = 'CREDIT BANK OF MOSCOW'
      self.homepage_url = 'http://mkb.ru/'
      self.live_url = 'https://mpi.mkb.ru/MPI_payment/'
      self.money_format = :cents
      #self.ssl_strict = false
      self.supported_cardtypes = [:visa, :master]
      self.supported_countries = ['RU']
      self.test_url = 'https://mpi.mkb.ru:9443/MPI_payment/'
      self.default_currency = '643'

      STANDARD_ERROR_CODE_MAPPING = {
          '0' => 'Approved',
          '1' => 'Disapproved',
          '2' => 'Error'
      }

      def initialize(options={})
        requires!(options, :password)
        super
      end

      def purchase(money, options={})
        post = {}
        add_invoice(post, money, options)
        # add_payment(post, payment)
        # add_address(post, payment, options)
        add_customer_data(post, options)

        commit('mpi_payment', post)
      end

      # def authorize(money, payment, options={})
      #   post = {}
      #   add_invoice(post, money, options)
      #   add_payment(post, payment)
      #   add_address(post, payment, options)
      #   add_customer_data(post, options)
      #
      #   commit('authonly', post)
      # end

      # def capture(money, authorization, options={})
      #   commit('capture', post)
      # end
      #
      # def refund(money, authorization, options={})
      #   commit('refund', post)
      # end

      # def void(authorization, options={})
      #   commit('void', post)
      # end
      #
      # def verify(credit_card, options={})
      #   MultiResponse.run(:use_first_response) do |r|
      #     r.process { authorize(100, credit_card, options) }
      #     r.process(:ignore_result) { void(r.authorization, options) }
      #   end
      # end
      #
      # def supports_scrubbing?
      #   true
      # end
      #
      # def scrub(transcript)
      #   transcript
      # end

      private

      def add_customer_data(post, options)
        post[:client_email] = options[:email]
      end

      # def add_address(post, creditcard, options)
      # end

      # = все поля здесь используются для подписи запроса MPI
      def add_invoice(post, money, options)
        post[:mid] = options[:mid]
        post[:aid] = options[:aid]
        post[:oid] = options[:oid]
        post[:amount] = amount(money)
        post[:currency] = (options[:currency] || currency(money))
      end

      SIGN_FIELDS = [
          :mid,
          :aid,
          :oid,
          :amount,
          :currency
      ]

      def signature(action, post)
        string_sign = @options[:password]
        if %w(mpi_payment reverse capture refund).include?(action)
          string_sign += SIGN_FIELDS.map {|key| post[key.to_sym]} * ""
        end
        hex_string = Digest::SHA1.hexdigest(string_sign)
        bin_string = hex_string.scan(/../).map { |x| x.hex.chr }.join
        Base64.encode64(bin_string).strip
      end

      # def add_payment(post, payment)
      # end

      def parse(body)
        {}
      end

      def commit(action, parameters)
        url = (test? ? test_url : live_url)
        response = parse(ssl_post(url, post_data(action, parameters)))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: AVSResult.new(code: response["some_avs_response_key"]),
          cvv_result: CVVResult.new(response["some_cvv_response_key"]),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response)
      end

      def message_from(response)
      end

      def authorization_from(response)
      end

      def post_data(action, parameters = {})
        parameters.merge!({
                              signature: signature(action, parameters)
                          }).to_query
      end

      def error_code_from(response)
        unless success_from(response)
          # TODO: lookup error code for this response
        end
      end
    end
  end
end
