# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Abstract base class for product compliance / hazmat rules. Ported from em-tasks' +RuleStrategy+.
      #
      # Subclasses must implement +#check(product)+ and return a Hash with the keys:
      #   - +:passed+ (Boolean)
      #   - +:reason+ (String, e.g. +"[OverSize]"+)
      #   - +:message+ (String, optional human-readable detail)
      class Strategy
        # Lenient default initializer mirrors the Python behaviour where
        # +Registry.get_rule(name, **kwargs)+ is allowed to forward unknown kwargs.
        def initialize(**_opts); end

        def check(_product)
          raise NotImplementedError, "#{self.class.name}#check must be implemented"
        end

        protected

        def passed_result
          { passed: true, reason: '', message: '' }
        end

        def failed_result(reason, message: '')
          { passed: false, reason: reason, message: message }
        end
      end
    end
  end
end
