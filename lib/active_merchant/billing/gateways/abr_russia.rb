require 'nokogiri'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class AbrRussiaGateway < Gateway

      self.display_name = 'Bank Russia'
      self.homepage_url = 'http://www.abr.ru/'
      self.test_url = 'https://pgtest.abr.ru:4443/exec'
      # TODO вставить живые данные
      self.live_url = 'https://example.com/live'
      self.money_format = :cents
      self.ssl_strict = true
      self.supported_cardtypes = [:visa, :master]
      self.supported_countries = ['RU']
      self.default_currency = '643'

      STANDARD_CODE_MAPPING = {
          '00' => 'Success',
          '10' => 'Operation not accessible or merchant not registered',
          '30' => 'Invalid message format (no mandatory fields, etc.)',
          '54' => 'Invalid operation',
          '95' => 'ON-PAYMENT or LOCKED, status remains the same',
          '96' => 'System error',
          '97' => 'Communication error with POS-driver'
      }

      def initialize(options={})
        requires!(options, :pem)
        super
      end

      def make_order(options={})
        commit('CreateOrder', options) do |xml|
          add_invoice(xml, options)
          add_url(xml, options)
        end
      end

      def authorize(options={})
      end

      def capture(options={})
      end

      def reverse(options={})
        commit('Reverse', options) do |xml|
          add_order_details(xml, options)
        end
      end

      def refund(options={})
        commit('Refund', options) do |xml|
          add_order_details(xml, options)
        end
      end

      def get_order_status(options={})
        commit('GetOrderStatus', options) do |xml|
          add_order_details(xml, options)
        end
      end


      private

      def build_xml(action, options)
        Nokogiri::XML::Builder.new do |xml|
          xml.TKKPG do
            xml.Request do
              xml.Operation_ action
              xml.Language_ 'RU'
              xml.Order do
                yield xml
              end
              xml.SessionID_ options[:session_id]
              if action == 'Reverse'
                xml.Amount_ amount(options[:amount])
                xml.Description_ options[:description]
              end
              xml.TranID options[:tran_id]
              if action == 'Refund'
                xml.Refund do
                  xml.Amount_ amount(options[:amount])
                  xml.Currency_ options[:currency] || currency(options[:amount])
                end
              end
            end
          end
        end.to_xml
      end

      def add_url(xml, options)
        xml.ApproveURL_ options[:approve_url]
        xml.CancelURL_ options[:cancel_url]
        xml.DeclineURL_ options[:decline_url]
      end

      def add_invoice(xml, options)
        xml.OrderType_ 'Purchase'
        xml.Merchant_ options[:abr_merchant]
        xml.Amount_ amount(options[:amount])
        xml.Currency_ options[:currency] || currency(options[:amount])
        xml.Description_ options[:description]
      end

      def add_order_details(xml, options)
        xml.Merchant_ options[:abr_merchant]
        xml.OrderID_ options[:order_id]
      end

      def parse(xml)
        response = {}

        Nokogiri::XML(CGI.unescapeHTML(xml)).xpath("//Response").children.each do |node|
          if node.text?
            next
          elsif (node.elements.size == 0)
            response[node.name.downcase.to_sym] = node.text
          else
            node.elements.each do |childnode|
              name = "#{node.name.downcase}_#{childnode.name.downcase}"
              response[name.to_sym] = childnode.text
            end
          end
        end

        response
      end

      def commit(action, parameters, &builder)
        url = (test? ? test_url : live_url)
        response = parse(ssl_post(url, build_xml(action, parameters, &builder)))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response)
        response[:status] == '00'
      end

      def message_from(response)
        STANDARD_CODE_MAPPING[response[:status]]
      end

      def error_code_from(response)
        unless success_from(response)
          response[:status]
        end
      end
    end
  end
end
