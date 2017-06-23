require 'nokogiri'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class MkbGateway < Gateway
      class_attribute :payment_test_url, :payment_live_url, :action_test_url, :action_live_url, :status_test_url, :status_live_url

      self.test_url = 'https://mpi.mkb.ru:9443/MPI_payment/'
      self.live_url = 'https://mpi.mkb.ru/MPI_payment/'

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
          '1' => 'Approved',
          '2' => 'Disapproved',
          '3' => 'Error'
      }

      def initialize(options={})
        requires!(options, :password)
        @test_url = options[:test_url] if options[:test_url]
        @live_url = options[:live_url] if options[:live_url]
        @action_test_url = options[:action_test_url] if options[:action_test_url]
        @action_live_url = options[:action_live_url] if options[:action_live_url]
        @status_test_url = options[:status_test_url] if options[:status_test_url]
        @status_test_url = options[:status_live_url] if options[:status_live_url]
        super
      end

      def make_order(options={})
        post = {}
        add_invoice(post, options)
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

      def get_order_status(options={})
        post = {}
        post[:login] = options[:login_status]
        post[:password] = options[:password_status]
        post[:Status] = 'Short'
        post[:MerID] = options[:mkb_mid]
        post[:OrderID] = options[:order_number]

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
        post[:client_mail] = options[:email]
      end

      def add_return_url(post, options)
        post[:redirect_url] = options[:return_url]
        post[:directposturl] = options[:directposturl]
      end

      def add_invoice(post, options)
        post[:mid] = options[:mkb_mid]
        post[:aid] = options[:mkb_aid]
        post[:oid] = options[:order_number]
        post[:currency] = self.default_currency
      end

      def add_amount(post, options)
        post[:amount] = normalize_amount(options[:amount])
      end

      # limited to 12 digits max and prefill leading zero
      def normalize_amount(amount)
        "%012d" % amount
      end

      def add_order_details(post, options)
        post[:MerID] = options[:mkb_mid]
        post[:AcqID] = options[:mkb_aid]
        post[:OrderID] = options[:order_number]
        post[:PurchaseAmt] = normalize_amount(options[:amount])
        post[:PurchaseCurrency] = self.default_currency
      end

      def add_actions_details(post, options)
        post[:AuthorizationNumber] = options[:external_order_id]
        post[:Amount] = normalize_amount(options[:amount])
        post[:MerRespURL] = options[:return_url]

        # static fields
        post[:PurchaseCurrencyExponent] = '2'
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

      SIGN_FIELDS_ACTIONS = [
          :MerID,
          :AcqID,
          :OrderID,
          :PurchaseAmt,
          :PurchaseCurrency
      ]

      def signature(action, post)
        string_sign = @options[:password]
        if %w(reverse capture refund).include?(action)
          string_sign += SIGN_FIELDS_ACTIONS.map {|key| post[key.to_sym]} * ""
        else
          string_sign += SIGN_FIELDS.map {|key| post[key.to_sym]} * ""
        end
        hex_string = Digest::SHA1.hexdigest(string_sign)
        bin_string = hex_string.scan(/../).map { |x| x.hex.chr }.join
        Base64.encode64(bin_string).strip
      end

      def parse(body, action)
        case action
          when 'mpi_payment'
            result = Nokogiri::HTML(body)
          when 'reverse', 'capture', 'refund'
            result = parse_actions(body)
          when 'status'
            result = parse_status(body)
        end

        result
      end

      def parse_actions(body)
        result = CGI::parse(body)
        result.map { |key, value| result[key] = value.join('') }
        result
      end

      def parse_status(body)
        results = { }
        xml = Nokogiri::XML(body)
        doc = xml.xpath("//order")
        doc.children.each do |element|
          results[element.name.underscore.downcase.to_sym] = element.text
        end
        results
      end

      def commit(action, parameters)
        case action
          when 'mpi_payment'
            url = (test? ? test_url : live_url)
          when 'reverse', 'capture', 'refund'
            url = (test? ? action_test_url : action_live_url)
          when 'status'
            url = (test? ? status_test_url : status_live_url)
        end

        response = parse(ssl_post(url, post_data(action, parameters)), action)

        Response.new(
          successful?(response, action),
          message_from(response, action, url, parameters),
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

      def successful?(response, action)
        case action
          when 'mpi_payment'
            if response.css("title")[0]
              response.css("title")[0].text == 'MKB payment'
            end
          when 'reverse', 'refund'
            response['ResponseCode'] == '1' && response['ReasonCode'] == '1'
          when 'capture'
            response['ResponseCode'] == '1' && response['ReasonCode'] == '17'
          when 'status'
            !response[:error].present?
        end
      end

      def message_from(response, action, url, parameters)
        if successful?(response, action)
          case action
            when 'mpi_payment'
              parameters.delete_if { |key, value| value.nil? }
              { form_url: "#{url}?#{parameters.to_query}" }
            when 'reverse', 'capture', 'refund'
              response
            when 'status'
              response
          end
        else

          case action
            when 'mpi_payment'
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
            when 'reverse', 'capture', 'refund'
              response
            when 'status'
              response
          end
        end
      end

      # def authorization_from(response)
      # end

      def post_data(action, parameters = {})
        sign = signature(action, parameters)
        parameters.merge!({**(%w(reverse capture refund).include?(action) ? { Signature: sign } : {signature: sign })}).to_query
      end

      def error_code_from(response)
        unless success_from(response)
          # TODO: lookup error code for this response
        end
      end
    end
  end
end
