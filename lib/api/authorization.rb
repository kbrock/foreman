require 'oauth/client/action_controller_request'

module Api
  class Authorization
    attr_reader :controller, :user_login

    def initialize(controller)
      @controller = controller
    end

    def authenticate
      unless SETTINGS[:login]
        # We assume we always have a user logged in,
        # if authentication is disabled, the user is the build-in admin account.
        User.current = User.find_by_login("admin")
      else
        authorization_method = oauth? ? :oauth : :http_basic
        User.current       ||= send(authorization_method) || (return false)
      end

      return true
    end

    def authorize
      User.current.allowed_to?(
        :controller => controller.params[:controller].gsub(/::/, "_").underscore,
        :action     => controller.params[:action])
    end

    def http_basic
      controller.authenticate_with_http_basic do |u, p|
        @user_login = u
        User.try_to_login(u, p)
      end
    end

    def oauth?
      !!(controller.request.authorization =~ /^OAuth/)
    end

    def oauth
      unless Setting['oauth_active']
        Rails.logger.debug 'Trying to authenticate with OAuth, but OAuth is not active'
        return nil
      end

      unless (incoming_key = OAuth::RequestProxy.proxy(controller.request).oauth_consumer_key) ==
          Setting['oauth_consumer_key']
        Rails.logger.debug "oauth_consumer_key should be '#{Setting['oauth_consumer_key']}'" <<
                               "but was '#{incoming_key}'"
        return nil
      end

      if OAuth::Signature.verify(controller.request, :consumer_secret => Setting['oauth_consumer_secret'])
        if Setting['oauth_map_users']
          User.find_by_login(user = controller.request.headers['foreman_user']).tap do |obj|
            Rails.logger.debug "Oauth: maping to user '#{user}' failed" if obj.nil?
          end
        else
          User.find_by_login 'admin'
        end
      else
        Rails.logger.debug "OAuth signature verification failed."
        return nil
      end
    end
  end
end
