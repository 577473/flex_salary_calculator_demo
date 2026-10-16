module Api
  module V1
    class LiquidacionesController < Api::BaseController
      PERIOD_PATTERN = /\A(\d{4})-(\d{2})\z/

      def index
        year, month = period_from_params!
        liquidaciones = Liquidacion.where(period_year: year, period_month: month)
        liquidaciones = liquidaciones.where(employee_id: params[:employee_id]) if params[:employee_id].present?
        liquidaciones = liquidaciones.includes(employee: :jobs).order(:employee_id, :id)
        render json: LiquidacionSerializer.list(liquidaciones)
      end

      def show
        liquidacion = Liquidacion.includes(:asignaciones, employee: :jobs).find(params[:id])
        render json: LiquidacionSerializer.show(liquidacion)
      end

      def calculate
        employee_ids = employee_ids_from_params!
        year, month = period_from_params!
        if Employee.where(id: employee_ids).count.zero?
          return render_problem(:unprocessable_content, "Unknown Employees",
                                "None of the requested employees exist")
        end

        envelope = CalculateLiquidacion.call(employee_ids: employee_ids,
                                             period: format("%04d-%02d", year, month))
        render json: EnvelopeSerializer.envelope(envelope)
      end

      private

      def employee_ids_from_params!
        ids = params[:employee_ids]
        raise ActionController::BadRequest, "employee_ids is required" if ids.blank?
        raise ActionController::BadRequest, "employee_ids must not be empty" if ids.empty?

        ids
      end

      def period_from_params!
        period = params[:period]
        raise ActionController::BadRequest, "period is required" if period.blank?

        match = PERIOD_PATTERN.match(period.to_s)
        raise ActionController::BadRequest, "period must use the YYYY-MM format" if match.nil?

        year = match[1].to_i
        month = match[2].to_i
        raise ActionController::BadRequest, "period month must be between 01 and 12" unless month.between?(1, 12)

        [ year, month ]
      end
    end
  end
end
