module Api
  module V1
    class EmployeesController < Api::BaseController
      def index
        render json: EmployeeSerializer.list(Employee.order(:name, :id))
      end

      def show
        employee = Employee.includes(:jobs).find(params[:id])
        render json: EmployeeSerializer.show(employee)
      end
    end
  end
end
