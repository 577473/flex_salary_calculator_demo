module Api
  class BaseController < ApplicationController
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
    rescue_from ActionController::BadRequest, with: :render_bad_request

    around_action :tag_request_id

    private

    def tag_request_id
      Rails.logger.tagged(request.request_id) { yield }
    end

    def render_problem(status, title, detail = nil, source: nil)
      error = { status: Rack::Utils.status_code(status), title: title }
      error[:detail] = detail unless detail.nil?
      error[:source] = source unless source.nil?

      render json: { errors: [ error ] }, status: status
    end

    def render_not_found(exception)
      render_problem(:not_found, "Not Found", exception.message)
    end

    def render_parameter_missing(exception)
      render_problem(:bad_request, "Parameter Missing", exception.message)
    end

    def render_bad_request(exception)
      render_problem(:bad_request, "Bad Request", exception.message)
    end

    def render_unprocessable(attribute_errors)
      errors = attribute_errors.flat_map do |attr, messages|
        Array(messages).map { |message| { title: "Unprocessable Entity", detail: message, source: attr } }
      end
      render json: { errors: errors }, status: :unprocessable_content
    end
  end
end
