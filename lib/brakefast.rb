require 'brakefast/version'
require 'brakefast/rack'
require 'uniform_notifier'

module Brakefast
  # TODO: move to config
  UniformNotifier.alert = true

  if defined? Rails::Railtie
    class BrakefastRailtie < Rails::Railtie
      initializer "brakefast.configure_rails_initialization" do |app|
        app.middleware.use Brakefast::Rack
      end
    end
  end

  class << self
    attr_writer :enable
    attr_reader :notification_collector, :whitelist
    # attr_accessor :add_footer

    available_notifiers =
      UniformNotifier::AVAILABLE_NOTIFIERS.map { |notifier| "#{notifier}=" }
    available_notifiers << { :to => UniformNotifier }
    # delegate *available_notifiers

    def enable?
      true
      # !!@enable
    end

    def start_request
      Thread.current[:brakefast_start] = true
      Thread.current[:brakefast_notifications] = []
    end

    def end_request
      Thread.current[:brakefast_start] = nil
      Thread.current[:brakefast_notifications] = nil
    end

    def start?
      Thread.current[:brakefast_start]
    end

    def notification?
      return false unless start?
      a = Thread.current[:brakefast_notifications]
      a && a.size > 0
    end

    def for_each_active_notifier_with_notification
      UniformNotifier.active_notifiers.each do |notifier|
        # notification_collector.collection.each do |notification|
          # notification.notifier = notifier
          # yield notification
        yield notifier
        # end
      end
    end

    def gather_inline_notifications
      responses = []
      # for_each_active_notifier_with_notification do |notification|
        # responses << notification.notify_inline
      for_each_active_notifier_with_notification do |notifier|
        notifications = Thread.current[:brakefast_notifications]
        next if notifications.nil?
        notifications.each do |n|
          responses << notifier.inline_notify(n)
        end
      end
      responses.join( "\n" )
    end
  end
end
