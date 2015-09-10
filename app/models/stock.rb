class Stock < ActiveRecord::Base
  require 'rest-client'
  require 'pp'
  STATUS = ['垃圾', '不考虑', '好', '未知']


  #获取靠谱股票推荐，需要符合以下条件：
  # 1. 10年高价是10年低价的3倍以上。
  # 2. 当前价格达到buy_price 上下10%左右。
  # 3. 当前价格达到best_price 上下10%左右。
  # #
  # Stock.get_useful_stock
  def self.get_useful_stock
    recommend_stocks = []
    very_recommend_stocks = []
    stocks = Stock.where status: '好'
    stocks.each do |stock|
      next unless stock.ten_years_top / stock.ten_years_low > 3
      if stock.current_price < stock.buy_price * 1.1
        recommend_stocks << [stock.code, stock.name]
      end

      if stock.current_price << stock.best_buy_price * 1.1
        very_recommend_stocks << [stock.code, stock.name]
      end
    end
    return recommend_stocks, very_recommend_stocks
  end

  # Stock.update_stock
  def self.update_stock
    str = ""
    Stock.all.each_with_index do |stock, i|
      i = i+1
      if str.blank?
        str = "#{stock.city_name}#{stock.code}"
      else
        str = "#{str},#{stock.city_name}#{stock.code}"
      end
      if i%300 == 0
        url = "http://hq.sinajs.cn/list=#{str}"
        pp url
        response = RestClient.get url
        ec = Encoding::Converter.new("gb18030", "UTF-8")
        content = ec.convert response.body
        content.split(';').each do |stock_info|
          stock_info.gsub!('var ', '')
          stock_info.gsub!('\n', '')
          next if stock_info.blank?
          split_stock_info = stock_info.split('=')
          values = split_stock_info[1]
          title = split_stock_info[0]
          next if values.blank?
          values = values.split(',')
          k = title.match /hq_str_(sh|sz)(\d{6})/
          stock = Stock.where(code: k[2]).first
          stock.current_price = ((values[3].to_f)*100).to_i
          # 今日最高
          topest_price = ((values[4].to_f)*100).to_i
          # 今日最低
          lowest_price = ((values[5].to_f)*100).to_i
          if stock.tgiten_years_low.to_i > lowest_price
            stock.ten_years_low = lowest_price
          end

          if stock.ten_years_top.to_i < topest_price
            stock.ten_years_top = topest_price
          end
          stock.save!

          str = ''
        end
      end
    end
  end


  def self.common_query options
    stocks = Stock.all
    stocks = stocks.where(code: options[:code]) unless options[:code].blank?
    stocks = stocks.where(name: options[:name]) unless options[:name].blank?
    stocks = stocks.where(status: options[:status]) unless options[:status].blank?
    stocks = stocks.where(city_name: options[:city_name]) unless options[:city_name].blank?

    stocks = stocks.where("current_price >= ?", options[:low_current_price]) unless options[:low_current_price].blank?
    stocks = stocks.where("current_price <= ?", options[:high_current_price]) unless options[:high_current_price].blank?

    stocks = stocks.where("ten_years_top >= ?", options[:low_ten_years_top]) unless options[:low_ten_years_top].blank?
    stocks = stocks.where("ten_years_top <= ?", options[:high_ten_years_top]) unless options[:high_ten_years_top].blank?

    stocks = stocks.where("ten_years_low >= ?", options[:low_ten_years_low]) unless options[:low_ten_years_low].blank?
    stocks = stocks.where("ten_years_low <= ?", options[:high_ten_years_low]) unless options[:high_ten_years_low].blank?

    stocks = stocks.where("buy_price >= ?", options[:low_buy_price]) unless options[:low_buy_price].blank?
    stocks = stocks.where("buy_price <= ?", options[:high_buy_price]) unless options[:high_buy_price].blank?

    stocks
  end


end


__END__


  # Stock.list_sz_data
  def self.list_sz_data
    # 每次请求100个股票
    str = ""

    Stock::SZ.each_with_index do |code, i|
      i = i+1
      code = code.strip
      str = "#{str},sz#{code}"
      if i%100 == 0
        url = "http://hq.sinajs.cn/list=#{str}"
        pp url
        response = RestClient.get url
        ec = Encoding::Converter.new("gb18030", "UTF-8")
        content = ec.convert response.body
        content.split(';').each do |stock_info|

          stock_info.gsub!('var ', '')
          next if stock_info.blank?
          values = eval(stock_info)
          pp values
          pp 'xxxxxxx'
          next if values.blank?
          values = values.split(',')
          k = stock_info.match /hq_str_sz(\d{6})/
          Stock.create_stock name: values[0],
                             code: k[1],
                             current_price: values[3],
                             city_name: 'sz'

        end

        str = ''
      end

    end
  end



  # Stock.list_sh_data
  def self.list_sh_data

    # 每次请求100个股票
    str = ""

    (600000..603998).each_with_index do |code, i|
      code  = code.to_s
      i = i+1
      code = code.strip
      str = "#{str},sh#{code}"
      if i%300 == 0
        url = "http://hq.sinajs.cn/list=#{str}"
        pp url
        response = RestClient.get url
        ec = Encoding::Converter.new("gb18030", "UTF-8")
        content = ec.convert response.body
        content.split(';').each do |stock_info|

          stock_info.gsub!('var ', '')
          next if stock_info.blank?
          values = eval(stock_info)
          pp values
          pp 'xxxxxxx'
          next if values.blank?
          values = values.split(',')
          k = stock_info.match /hq_str_sh(\d{6})/
          Stock.create_stock name: values[0],
                             code: k[1],
                             current_price: values[3],
                             city_name: 'sh'

        end
        str = ''
      end
    end

    def self.create_stock options
    stock = Stock.where(code: options[:code]).first
    if stock.blank?
      s = Stock.new name: options[:name],
                    code: options[:code],
                    current_price: ((options[:current_price].to_f)*100).to_i,
                    city_name: options[:city_name]
      s.save!
    else
      stock.current_price = ((options[:current_price].to_f)*100).to_i
      stock.save!
    end
  end
  end