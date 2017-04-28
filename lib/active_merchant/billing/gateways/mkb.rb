require 'nokogiri'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class MkbGateway < Gateway
      class_attribute :payment_test_url, :payment_live_url, :action_test_url, :action_live_url, :status_test_url, :status_live_url

      self.payment_test_url = 'https://mpi.mkb.ru:9443/MPI_payment/'
      self.payment_live_url = 'https://mpi.mkb.ru/MPI_payment/'

      self.action_test_url = 'https://ts-ecomweb-test.mcb.ru/SENTRY/PaymentGateway/Application/FinancialProcessing.aspx'
      self.action_live_url = 'https://ts-ecomweb.mcb.ru/SENTRY/PaymentGateway/Application/FinancialProcessing.aspx'

      self.status_test_url = 'https://mpi.mkb.ru:9443/finoperate/dogetorderstatusservlet'
      self.status_live_url = 'https://mpi.mkb.ru:8443/finoperate/dogetorderstatusservlet'

      self.display_name = 'CREDIT BANK OF MOSCOW'
      self.homepage_url = 'http://mkb.ru/'
      self.money_format = :cents
      #self.ssl_strict = false
      self.supported_cardtypes = [:visa, :master]
      self.supported_countries = ['RU']
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

      def payment_page(options={})
        post = {}
        add_invoice(post, options)
        # add_payment(post, payment)
        # add_address(post, payment, options)
        add_customer_data(post, options)
        add_amount(post, options)
        add_return_url(post, options)

        commit('mpi_payment', post)
      end

      def capture(options={})
        post = {}
        post[:Action] = 'Capture'
        add_order_details(post, options)
        add_actions_details(post, options)

        commit('capture', post)
      end

      def refund(options={})
        post = {}
        post[:Action] = 'Refund'
        add_order_details(post, options)
        add_actions_details(post, options)

        commit('refund', post)
      end

      def reverse(options={})
        post = {}
        post[:Action] = 'Reverse'
        add_order_details(post, options)
        add_actions_details(post, options)

        commit('reverse', post)
      end

      def status(options={})
        post = {}
        post[:login] = options[:login]
        post[:password] = options[:password]
        post[:Status] = 'Short'
        post[:MerID] = options[:mid]
        post[:OrderID] = options[:oid]

        commit('status', post)
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

      def add_return_url(post, options)
        post[:redirect_url] = options[:return_url]
      end

      # def add_address(post, creditcard, options)
      # end

      def add_invoice(post, options)
        post[:mid] = options[:mid]
        post[:aid] = options[:aid]
        post[:oid] = options[:oid]
        post[:currency] = options[:currency]
      end

      def add_amount(post, options)
        post[:amount] = options[:amount]
      end

      def add_order_details(post, options)
        post[:MerID] = options[:mid]
        post[:AcqID] = options[:aid]
        post[:OrderID] = options[:oid]
        post[:PurchaseAmt] = options[:amount]
        post[:PurchaseCurrency] = options[:currency]
      end

      def add_actions_details(post, options)
        post[:AuthorizationNumber] = options[:transaction_number]
        post[:Amount] = options[:amount]
        post[:MerRespURL] = options[:response_url]

        # static fields
        post[:PurchaseCurrencyExponent] = 2
        post[:Version] = '1.0.0'
        post[:SignatureMethod] = 'SHA1'
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

      def parse(body, action)
        case action
          when 'mpi_payment'
            result = Nokogiri::HTML(body)
          when 'status'
            result = parse_status(body)
        end

        result
      end

      def parse_status(body)
        results = { }
        xml = Nokogiri::XML(body)
        doc = xml.xpath("//order/orderId")
        doc.children.each do |element|
          results[element.name.downcase.to_sym] = element.text
        end
        doc = xml.xpath("//order/status")
        doc.children.each do |element|
          results[element.name.downcase.to_sym] = element.text
        end
        results
      end

      def commit(action, parameters)
        case action
          when 'mpi_payment'
            url = (test? ? payment_test_url : payment_live_url)
          when 'reverse', 'capture', 'refund'
            url = (test? ? action_test_url : action_live_url)
          when 'status'
            url = (test? ? status_test_url : status_live_url)
        end

        response = parse(ssl_post(url, post_data(action, parameters)), action)

        Response.new(
          successful?(response),
          message_from(response),
          #response,
          # authorization: authorization_from(response),
          # avs_result: AVSResult.new(code: response["some_avs_response_key"]),
          # cvv_result: CVVResult.new(response["some_cvv_response_key"]),
          test: test?
          #error_code: error_code_from(response)
        )
      end

      # def success_from(response)
      # end

      def successful?(response)
        true
        # if response.css("title")[0]
        #   response.css("title")[0].text == 'MKB payment'
        # end
      end

      def message_from(response)
        if successful?(response)
          "Success"
        else
          # TODO нормально парсить ошибки
          errors = []
          if response.css("h1")
            response.css("h1").each_with_index { |e, i| errors << "Errors: #{e.text} - #{response.css("h3")[i].text}"}
          end

          if response.css("p")
            response.css('p').each do |el|
              errors << el.text
            end
          end
          errors
        end
      end

      # def authorization_from(response)
      # end

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
