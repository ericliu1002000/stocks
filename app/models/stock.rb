class Stock < ActiveRecord::Base
  has_many :stock_price_days
  require 'rest-client'
  require 'pp'
  STATUS = ['垃圾', '不考虑', '好', '未知']
  #以后考虑放开
  # ZANBUKAOLV1 = ['吉祥航空', '潍柴动力']
  ZANBUKAOLV1 = []

  #不考虑放开
  ZANBUKAOLV2 = ['平安银行', '壹桥海参', '庞大集团', '荣安地产']


  # Stock.set_ten_years_price
  def self.set_ten_years_price
    Stock.all.each do |stock|
      # 以开盘价、收盘价做为最高、最低值
      # lowest_stock = stock.stock_price_days.order("end_price" => :asc).first
      # highest_stock = stock.stock_price_days.order('end_price' => :desc).first
      # next if lowest_stock.blank?
      # next if highest_stock.blank?
      # stock.ten_years_low = lowest_stock.end_price > lowest_stock.start_price ? lowest_stock.start_price : lowest_stock.end_price
      # stock.ten_years_top = highest_stock.end_price > highest_stock.start_price ? highest_stock.end_price : highest_stock.start_price

      # 以最高价，最低价做为最高、最低值

      lowest_stock = stock.stock_price_days.order("low_price" => :asc).first
      highest_stock = stock.stock_price_days.order('top_price' => :desc).first
      next if lowest_stock.blank?
      next if highest_stock.blank?
      stock.ten_years_low = lowest_stock.low_price
      stock.ten_years_top = highest_stock.top_price
      stock.buy_price = (stock.ten_years_low * 1.0).to_i
      stock.status = "好"
      stock.save!
    end
  end



  # Stock.update_and_get_useful_stock
  def self.update_and_get_useful_stock
    Stock.update_stock
    pp Stock.get_useful_stock
  end

  #获取靠谱股票推荐，需要符合以下条件：
  # 1. 10年高价是10年低价的3倍以上。
  # 2. 当前价格达到buy_price 上下10%左右。
  # 3. 当前价格达到best_price 上下10%左右。
  # #
  # Stock.get_useful_stock
  def self.get_useful_stock
    recommend_stocks = []
    very_recommend_stocks = []
    lowest = []
    stocks = Stock.where status: '好'
    stocks.each do |stock|
      if stock.ten_years_low == 0
        pp "#{stock.code}  :分母为 0 "
        next
      end

      #上市时间短不推荐
      if stock.stock_price_days.count < 300
        next
      end

      # 10元以上的股票不推荐
      if stock.current_price > 1000
        next
      end

      # 波动幅度小不推荐
      next unless stock.ten_years_top / stock.ten_years_low > 3

      #停牌不推荐
      next if stock.current_price == 0

      #设置暂不考虑的，不推荐
      next if Stock::ZANBUKAOLV1.include? stock.name
      next if Stock::ZANBUKAOLV2.include? stock.name

      # 接近底部价推荐
      if stock.current_price < (stock.buy_price * 1.3).to_i
        # pp stock.current_price
        # pp stock.buy_price * 1.1
        recommend_stocks << [stock.code, stock.name, stock.current_price]
      end

      # if stock.current_price < (stock.best_buy_price||0 * 1.1).to_i
      #   very_recommend_stocks << [stock.code, stock.name]
      # end
      #
      # if stock.current_price == stock.ten_years_low
      #   lowest << [stock.code, stock.name]
      # end
    end
    # return  very_recommend_stocks,lowest, recommend_stocks
    recommend_stocks.sort!{ |x,y| y[2] <=> x[2] }
    pp recommend_stocks
    return   recommend_stocks
  end

  # Stock.update_stock
  def self.update_stock
    Stock.transaction do
      str = ""
      Stock.all.each_with_index do |stock, i|
        i = i+1
        if str.blank?
          str = "#{stock.city_name}#{stock.code}"
        else
          str = "#{str},#{stock.city_name}#{stock.code}"
        end
        if i%300 == 0
          # pp "开始执行第#{i}条数据"
          url = "http://hq.sinajs.cn/list=#{str}"
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
            next if stock.current_price == 0
            # 今日最高
            topest_price = ((values[4].to_f)*100).to_i
            # 今日最低
            lowest_price = ((values[5].to_f)*100).to_i

            if stock.ten_years_low.to_i > lowest_price && lowest_price > 0
              stock.ten_years_low = lowest_price
            end
            if stock.ten_years_top.to_i < topest_price && topest_price > 0
              stock.ten_years_top = topest_price
            end
            stock.save!
            str = ''
          end
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

  def update_info options
    # (:ten_years_top, :ten_years_low, :buy_price)
    self.ten_years_top=options[:ten_years_top] unless options[:ten_years_top].blank?
    self.ten_years_low=options[:ten_years_low] unless options[:ten_years_low].blank?
    self.buy_price=options[:buy_price] unless options[:buy_price].blank?
    self.save!
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