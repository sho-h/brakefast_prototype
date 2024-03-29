require 'brakeman'

module Brakefast
  class Rack
    def initialize(app)
      @app = app
      tracker = Brakeman.run(Rails.root.to_s)
      report = tracker.report.format(:to_hash)
      [:errors, :controller_warnings, :generic_warnings, :model_warnings].each do |k|
        report[k].each do |e|
          klass = e.class || e.controller || e.model
          method = e.method
          if klass && method
            msg = e.message
            mod = Module.new
            mod.module_eval %Q{
              def #{method}
                s = "vulnerability found in #{e.file}:#{e.line} - #{msg}"
                Thread.current[:brakefast_notifications] << s
=begin
                # for debug
                File.open("/tmp/1.log", "w") do |f|
                  f.write("vulnerability found in #{e.file}:#{e.line} - #{msg}")
                end
=end
                super
              end
            }

            name = klass.to_s.gsub("::", "__") + "BrakefastHook"
            Brakefast.const_set(name, mod)
            ::Object.const_get(klass).class_eval %Q{
              prepend Brakefast::#{name}
            }
          end
        end
      end
    end

    def call(env)
      return @app.call(env) unless Brakefast.enable?
      Brakefast.start_request
      status, headers, response = @app.call(env)

      if Brakefast.notification?
        if !file?(headers) && !sse?(headers) && !empty?(response) &&
            status == 200 && !response_body(response).frozen? && html_request?(headers, response)
          response_body = response_body(response)
          # append_to_html_body(response_body, footer_note) if Brakefast.add_footer?
          append_to_html_body(response_body, Brakefast.gather_inline_notifications)
          headers['Content-Length'] = response_body.bytesize.to_s
        end
        # Brakefast.perform_out_of_channel_notifications(env)
      end
      [status, headers, response_body ? [response_body] : response]
    ensure
      Brakefast.end_request
    end

    def append_to_html_body(response_body, content)
      if response_body.include?('</body>')
        position = response_body.rindex('</body>')
        response_body.insert(position, content)
      else
        response_body << content
      end
    end

    private

    # fix issue if response's body is a Proc
    def empty?(response)
      # response may be ["Not Found"], ["Move Permanently"], etc.
      if rails?
        (response.is_a?(Array) && response.size <= 1) ||
          !response.respond_to?(:body) ||
          !response_body(response).respond_to?(:empty?) ||
          response_body(response).empty?
      else
        body = response_body(response)
        body.nil? || body.empty?
      end
    end

    def footer_note
      "<div #{footer_div_attributes}>" + Bullet.footer_info.uniq.join("<br>") + "</div>"
    end

    def file?(headers)
      headers["Content-Transfer-Encoding"] == "binary"
    end

    def sse?(headers)
      headers["Content-Type"] == "text/event-stream"
    end

    def html_request?(headers, response)
      headers['Content-Type'] && headers['Content-Type'].include?('text/html') && response_body(response).include?("<html")
    end

    def response_body(response)
      if rails?
        Array === response.body ? response.body.first : response.body
      else
        response.first
      end
    end

    def footer_div_attributes
<<EOF
data-is-bullet-footer ondblclick="this.parentNode.removeChild(this);" style="position: fixed; bottom: 0pt; left: 0pt; cursor: pointer; border-style: solid; border-color: rgb(153, 153, 153);
 -moz-border-top-colors: none; -moz-border-right-colors: none; -moz-border-bottom-colors: none;
 -moz-border-left-colors: none; -moz-border-image: none; border-width: 2pt 2pt 0px 0px;
 padding: 5px; border-radius: 0pt 10pt 0pt 0px; background: none repeat scroll 0% 0% rgba(200, 200, 200, 0.8);
 color: rgb(119, 119, 119); font-size: 18px; font-family: 'Arial', sans-serif; z-index:9999;"
EOF
    end

    def rails?
      @rails ||= defined? ::Rails
    end
  end
end
