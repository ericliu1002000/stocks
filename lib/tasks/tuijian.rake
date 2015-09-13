namespace :tuijian do
	desc "获取推荐股  rake tuijian:update_and_get_useful_stock RAILS_ENV=production"
	task :update_and_get_useful_stock => :environment do
    # 更新现价
    Stock.update_stock

    # 设置10年最高价，最低价
		Stock.set_ten_years_price


    #获取推荐股
		Stock.get_useful_stock
  end

	desc "更新每天价格  rake tuijian:update_price_day RAILS_ENV=production"
	task :update_price_day => :environment do
		StockPriceDay.update_price_day
	end


end


