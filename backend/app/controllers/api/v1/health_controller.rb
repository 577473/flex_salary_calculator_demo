module Api
  module V1
    class HealthController < Api::BaseController
      def show
        render json: { status: "ok" }
      end
    end
  end
end
