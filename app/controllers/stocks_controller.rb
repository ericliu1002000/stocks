class StocksController < ApplicationController

  def index
    @stocks = Stock.common_query params.permit(:code, :name, :low_current_price, :high_current_price, :low_ten_years_top,
                                 :high_ten_years_top, :low_ten_years_low, :high_ten_years_low, :low_buy_price, :high_buy_price,
                                 :status, :city_name)
    @stocks = @stocks.paginate(per_page: params[:per_page]||20, page: params[:page])
  end

  def edit
    @stock = Stock.find_by_id(params[:id])
  end

  def update
    stock = Stock.find_by_id(params[:id])
    # begin
    stock.update_info params.permit(:ten_years_top, :ten_years_low, :buy_price)
    redirect_to action: :index
    # rescue Exception=>e
    #   render :edit
    # end
  end

  def display

  end

end