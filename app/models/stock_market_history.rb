class StockMarketHistory < ActiveRecord::Base

  # 2016 季度1
  # http://vip.stock.finance.sina.com.cn/corp/go.php/vMS_MarketHistory/stockid/601989.phtml?year=2016&jidu=1
  # 2016 季度2
  # http://vip.stock.finance.sina.com.cn/corp/go.php/vMS_MarketHistory/stockid/601989.phtml?year=2016&jidu=2
  # 2016 季度3
  # http://vip.stock.finance.sina.com.cn/corp/go.php/vMS_MarketHistory/stockid/601989.phtml?year=2016&jidu=3
  # http://vip.stock.finance.sina.com.cn/corp/go.php/vMS_MarketHistory/stockid/601989.phtml?year=2016&jidu=4

  # 下载所以A股交易数据
  # StockMarketHistory.download_all_a_stocks_all_trade_info
  def self.download_all_a_stocks_all_trade_info
    Stock.where(stock_type: 1).each do |stock|
      self.download_a_stock_all_trade_info stock.id
    end
  end

  # 下载A股id在start_id和end_id之间的股票的所有交易数据
  # StockMarketHistory.download_a_stock_all_trade_info_between 1, 100
  def self.download_a_stock_all_trade_info_between start_id, end_id
    Stock.where(stock_type: 1).where("id >= ? and id < ?", start_id, end_id).each do |stock|
      self.download_a_stock_all_trade_info stock.id
    end
  end

  # 下载A股中 某股所有交易数据
  # StockMarketHistory.download_a_stock_all_trade_info 5
  def self.download_a_stock_all_trade_info stock_id
    Time.now.year.downto 2004 do |year|
      1.upto 4 do |jidu|
        self.download_a_stock_trade_info stock_id, year, jidu
      end
    end
  end

  # 下载A股 某股 某年 某季度 交易数据
  # StockMarketHistory.download_a_stock_trade_info 5, 2016, 1
  def self.download_a_stock_trade_info stock_id, year, jidu
    self.transaction do

      trade_date_condition =
      case jidu
        when 1
          "trade_date >= '#{year}-01-01' and trade_date <= '#{year}-03-31'"
        when 2
          "trade_date >= '#{year}-04-01' and trade_date <= '#{year}-06-30'"
        when 3
          "trade_date >= '#{year}-07-01' and trade_date <= '#{year}-09-30'"
        when 4
          "trade_date >= '#{year}-10-01' and trade_date <= '#{year}-12-31'"
      end
      return unless self.where(stock_id: stock_id).where(trade_date_condition).blank? # 如果此股票此季度有数据则跳过

      stock = Stock.find(stock_id)
      uri = "http://vip.stock.finance.sina.com.cn/corp/go.php/vMS_MarketHistory/stockid/#{stock.code}.phtml?year=#{year}&jidu=#{jidu}"
      response = RestClient.get uri
      ec = Encoding::Converter.new("GBK", "UTF-8")
      doc = ec.convert response.body
      doc = Nokogiri::HTML(doc)
      table_content = doc.xpath("//table").select{|x|x.to_s.include? 'FundHoldSharesTable'}[0]
      return if table_content.blank?
      trs_content_doc = Nokogiri::HTML(table_content.to_s)
      trs_content_doc.xpath("//tr").each_with_index do |tr, index| # 获取数据抬头
        next if index == 0 || index == 1
        td_doc = Nokogiri::HTML tr.to_s
        tds = td_doc.xpath("//td")
        trade_date = Nokogiri::Slop(tds[0].to_s.encode("utf-8")).td.content.strip
        if StockMarketHistory.where( stock_id: stock_id, trade_date: trade_date ).blank?
          StockMarketHistory.create! stock_id: stock_id,
                                     trade_date: trade_date,
                                     open_price: Nokogiri::Slop(tds[1].to_s.encode("utf-8")).td.content.strip,
                                     peak_price: Nokogiri::Slop(tds[2].to_s.encode("utf-8")).td.content.strip,
                                     close_price: Nokogiri::Slop(tds[3].to_s.encode("utf-8")).td.content.strip,
                                     bottom_price: Nokogiri::Slop(tds[4].to_s.encode("utf-8")).td.content.strip,
                                     trade_volume: Nokogiri::Slop(tds[5].to_s.encode("utf-8")).td.content.strip,
                                     trade_ammount: Nokogiri::Slop(tds[6].to_s.encode("utf-8")).td.content.strip

        end
      end
    end
  end

end

