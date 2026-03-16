import Cocoa
import Foundation

// MARK: - ============ 黄金相关数据模型 ============
struct PriceInfo {
    var price: String = "--"
    var yesterdayPrice: String = "--"
    var changeRate: String = ""
    var changeAmount: String = ""

    var isUp: Bool {
        if let rate = Double(changeRate.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")) {
            return rate >= 0
        }
        return changeRate.hasPrefix("+") || (!changeRate.hasPrefix("-") && !changeRate.isEmpty)
    }
}

struct GoldPrices {
    var minsheng = PriceInfo()
    var icbc = PriceInfo()
    var zheshang = PriceInfo()
    var london = PriceInfo()
    var newyork = PriceInfo()
    var lastUpdate: Date?

    func priceInfo(for key: String) -> PriceInfo {
        switch key {
        case "minsheng": return minsheng
        case "icbc":     return icbc
        case "zheshang": return zheshang

        case "london":   return london
        case "newyork":  return newyork
        default: return PriceInfo()
        }
    }
}

struct GoldAPIResponse: Codable {
    struct ResultData: Codable {
        struct Datas: Codable {
            let price: String?
            let yesterdayPrice: String?
            let upAndDownRate: String?
            let upAndDownAmt: String?
        }
        let datas: Datas?
    }
    let resultData: ResultData?
}

// MARK: - ============ 基金相关数据模型 ============
struct FundInfo: Codable, Identifiable {
    var id: String { code }
    let code: String
    let name: String
    let type: String
    var netValue: String = "--"        // 单位净值
    var netValueDate: String = ""      // 净值日期
    var estimatedValue: String = "--"  // 估算净值
    var estimatedRate: String = ""     // 估算涨跌幅
    var lastUpdate: Date?

    var isUp: Bool {
        if let rate = Double(estimatedRate.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")) {
            return rate >= 0
        }
        return estimatedRate.hasPrefix("+") || (!estimatedRate.hasPrefix("-") && !estimatedRate.isEmpty)
    }

    init(code: String, name: String = "", type: String = "未分类") {
        self.code = code
        self.name = name
        self.type = type
    }
}

struct FundCategory: Codable, Identifiable {
    var id: String { name }
    let name: String
    var funds: [String] = []  // 基金代码列表
}

// 基金API响应解析
struct FundAPIResponse {
    let code: String
    let name: String
    let netValue: String
    let netValueDate: String
    let estimatedValue: String
    let estimatedRate: String
}

// MARK: - ============ 黄金价格服务 ============
class GoldPriceService {
    static let shared = GoldPriceService()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    func fetchAllPrices() async -> GoldPrices {
        var prices = GoldPrices()

        async let minsheng      = fetchMinsheng()
        async let icbc          = fetchICBC()
        async let zheshang      = fetchZheshang()
        async let international = fetchInternationalGold()

        prices.minsheng = await minsheng
        prices.icbc     = await icbc
        prices.zheshang = await zheshang

        let intlPrices = await international
        prices.london  = intlPrices.london
        prices.newyork = intlPrices.newyork

        prices.lastUpdate = Date()
        return prices
    }

    private func fetchMinsheng() async -> PriceInfo {
        var info = PriceInfo()
        guard let url = URL(string: "https://api.jdjygold.com/gw/generic/hj/h5/m/latestPrice") else { return info }
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(GoldAPIResponse.self, from: data)
            if let datas = response.resultData?.datas {
                info.price = datas.price ?? "--"
                info.yesterdayPrice = datas.yesterdayPrice ?? "--"
                info.changeRate = datas.upAndDownRate ?? ""
                info.changeAmount = datas.upAndDownAmt ?? ""
            }
        } catch {
            print("Minsheng fetch error: \(error)")
        }
        return info
    }

    private func fetchICBC() async -> PriceInfo {
        var info = PriceInfo()
        guard let url = URL(string: "https://api.jdjygold.com/gw2/generic/jrm/h5/m/icbcLatestPrice?productSku=2005453243") else { return info }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["reqData": ["productSku": "2005453243"]])
        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(GoldAPIResponse.self, from: data)
            if let datas = response.resultData?.datas {
                info.price = datas.price ?? "--"
                info.yesterdayPrice = datas.yesterdayPrice ?? "--"
                info.changeRate = datas.upAndDownRate ?? ""
                info.changeAmount = datas.upAndDownAmt ?? ""
            }
        } catch {
            print("ICBC fetch error: \(error)")
        }
        return info
    }

    private func fetchZheshang() async -> PriceInfo {
        var info = PriceInfo()
        guard let url = URL(string: "https://api.jdjygold.com/gw2/generic/jrm/h5/m/stdLatestPrice?productSku=1961543816") else { return info }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["reqData": ["productSku": "1961543816"]])
        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(GoldAPIResponse.self, from: data)
            if let datas = response.resultData?.datas {
                info.price = datas.price ?? "--"
                info.yesterdayPrice = datas.yesterdayPrice ?? "--"
                info.changeRate = datas.upAndDownRate ?? ""
                info.changeAmount = datas.upAndDownAmt ?? ""
            }
        } catch {
            print("Zheshang fetch error: \(error)")
        }
        return info
    }

    private func fetchInternationalGold() async -> (london: PriceInfo, newyork: PriceInfo) {
        var london = PriceInfo()
        var newyork = PriceInfo()

        // 尝试多个API源
        let apiUrls = [
            "https://hq.sinajs.cn/list=hf_XAU,hf_GC",
            "http://hq.sinajs.cn/list=hf_XAU,hf_GC"
        ]
        
        for apiUrl in apiUrls {
            guard let url = URL(string: apiUrl) else { continue }

        var request = URLRequest(url: url)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10
            
            do {
                let (data, response) = try await session.data(for: request)
                
                // 检查HTTP状态码
                if let httpResponse = response as? HTTPURLResponse {
                    guard (200...299).contains(httpResponse.statusCode) else {
                        print("International gold API returned status: \(httpResponse.statusCode)")
                        continue
                    }
                }
                
                // 尝试多种编码
                let text: String?
                if let utf8Text = String(data: data, encoding: .utf8), !utf8Text.isEmpty {
                    text = utf8Text
                } else if let gbkText = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
                    text = gbkText
                } else if let asciiText = String(data: data, encoding: .ascii) {
                    text = asciiText
                } else {
                    text = nil
                }
                
                guard let text = text, !text.isEmpty else {
                    print("International gold: Failed to decode response data")
                    continue
                }
                
                // 解析数据
                let lines = text.components(separatedBy: ";")
                var foundLondon = false
                var foundNewyork = false
                
                for line in lines {
                    if line.contains("hf_XAU") && !foundLondon {
                        london = parseSinaData(line)
                        if !london.price.isEmpty && london.price != "--" {
                            foundLondon = true
                        }
                    } else if line.contains("hf_GC") && !foundNewyork {
                        newyork = parseSinaData(line)
                        if !newyork.price.isEmpty && newyork.price != "--" {
                            foundNewyork = true
                        }
                    }
                    
                    // 如果两个都找到了，可以提前退出
                    if foundLondon && foundNewyork {
                        break
                    }
                }
                
                // 如果成功获取到数据，退出循环
                if foundLondon || foundNewyork {
                    print("International gold: Successfully fetched (London: \(foundLondon), Newyork: \(foundNewyork))")
                    break
                } else {
                    print("International gold: No valid data found in response: \(text.prefix(200))")
                }
                
        } catch {
                print("International gold fetch error for \(apiUrl): \(error.localizedDescription)")
                continue
            }
        }
        
        // 如果还是没数据，尝试备用API
        if london.price == "--" && newyork.price == "--" {
            // 尝试使用其他数据源（如果需要）
            print("International gold: All APIs failed, trying alternative sources...")
        }

        return (london, newyork)
    }

    private func parseSinaData(_ line: String) -> PriceInfo {
        var info = PriceInfo()
        
        // 清理行数据，移除可能的换行符和空白
        let cleanedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 查找数据部分（在引号之间）
        guard let start = cleanedLine.firstIndex(of: "\""),
              let end = cleanedLine.lastIndex(of: "\"") else {
            print("parseSinaData: No quotes found in line: \(cleanedLine.prefix(100))")
            return info
        }
        
        let content = String(cleanedLine[cleanedLine.index(after: start)..<end])
        let parts = content.components(separatedBy: ",")

        // 新浪API数据格式通常是：名称,当前价,昨收,开盘,最高,最低,最新,结算,持仓,买价,卖价,时间,日期
        // 或者：var hq_str_hf_XAU="伦敦金,当前价,昨收,..."
        guard parts.count > 7 else {
            print("parseSinaData: Not enough parts (\(parts.count)), expected > 7. Content: \(content.prefix(100))")
            return info
        }
        
        // 尝试多个位置获取当前价格（不同API格式可能不同）
        var currentPrice: Double? = nil
                var yesterdayPrice: Double? = nil
        
        // 通常 parts[0] 是名称，parts[1] 是当前价，parts[2] 是昨收
        // 但有些格式 parts[1] 是当前价，parts[2] 是昨收
        for i in 1..<min(parts.count, 10) {
            if let price = Double(parts[i]), price > 0 {
                if currentPrice == nil {
                    currentPrice = price
                } else if yesterdayPrice == nil && price != currentPrice {
                    yesterdayPrice = price
                    break
                }
            }
        }
        
        // 如果没找到，尝试标准位置
        if currentPrice == nil {
            if let price = Double(parts[1]), price > 0 {
                currentPrice = price
            } else if parts[0].allSatisfy({ $0.isNumber || $0 == "." }) {
                if let price = Double(parts[0]), price > 0 {
                    currentPrice = price
                }
            }
        }
        
        if yesterdayPrice == nil {
            if let price = Double(parts[2]), price > 0 {
                yesterdayPrice = price
            } else if let price = Double(parts[7]), price > 0 {
                yesterdayPrice = price
            }
        }
        
        // 设置价格
        if let cp = currentPrice {
            info.price = String(format: "%.2f", cp)

                if let yp = yesterdayPrice {
                    info.yesterdayPrice = String(format: "%.2f", yp)
                let change = cp - yp
                    let changePercent = (change / yp) * 100
                    let sign = change >= 0 ? "+" : ""
                    info.changeAmount = "\(sign)\(String(format: "%.2f", change))"
                    info.changeRate = "\(sign)\(String(format: "%.2f", changePercent))%"
            } else {
                // 即使没有昨收价，也显示当前价
                print("parseSinaData: No yesterday price found, using current price only")
                }
        } else {
            print("parseSinaData: Failed to parse price from parts: \(parts.prefix(5))")
            }
        
        return info
    }
}

// MARK: - ============ 基金服务 ============
class FundService {
    static let shared = FundService()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    // 获取单个基金信息
    func fetchFundInfo(code: String) async -> FundInfo? {
        // 天天基金API
        guard let url = URL(string: "http://fundgz.1234567.com.cn/js/\(code).js?rt=\(Date().timeIntervalSince1970)") else {
            return nil
        }

        do {
            let (data, _) = try await session.data(from: url)
            if let text = String(data: data, encoding: .utf8) {
                // 解析JSONP格式: jsonpgz({"fundcode":"000001","name":"华夏成长",...})
                if let jsonStart = text.firstIndex(of: "("),
                   let jsonEnd = text.lastIndex(of: ")") {
                    let jsonString = String(text[text.index(after: jsonStart)..<jsonEnd])
                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] {
                        var fund = FundInfo(code: code, name: json["name"] ?? "", type: "未分类")
                        fund.netValue = json["dwjz"] ?? "--"
                        fund.netValueDate = json["jzrq"] ?? ""
                        fund.estimatedValue = json["gsz"] ?? "--"
                        fund.estimatedRate = json["gszzl"] ?? ""
                        fund.lastUpdate = Date()
                        return fund
                    }
                }
            }
        } catch {
            print("Fund fetch error for \(code): \(error)")
        }
        return nil
    }

    // 批量获取基金信息
    func fetchAllFunds(codes: [String]) async -> [FundInfo] {
        var results: [FundInfo] = []

        await withTaskGroup(of: FundInfo?.self) { group in
            for code in codes {
                group.addTask {
                    return await self.fetchFundInfo(code: code)
                }
            }

            for await result in group {
                if let fund = result {
                    results.append(fund)
                }
            }
        }

        return results
    }
}

// MARK: - ============ A股相关数据模型 ============
struct StockInfo: Codable, Identifiable {
    var id: String { code }
    let code: String
    let name: String
    var currentPrice: String = "--"      // 当前价
    var yesterdayPrice: String = "--"    // 昨收
    var changeAmount: String = ""        // 涨跌额
    var changeRate: String = ""          // 涨跌幅
    var volume: String = ""              // 成交量
    var amount: String = ""              // 成交额
    var lastUpdate: Date?
    
    /// 解析后的涨跌幅数值（无 %、+ 等）
    var changeRateValue: Double? {
        let s = changeRate.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == "--" { return nil }
        return Double(s)
    }
    /// 涨（严格大于 0）
    var isUp: Bool { (changeRateValue ?? 0) > 0 }
    /// 跌（严格小于 0）
    var isDown: Bool { (changeRateValue ?? 0) < 0 }
    /// 平（等于 0）
    var isFlat: Bool { changeRateValue == 0 }
    
    init(code: String, name: String = "") {
        self.code = code
        self.name = name
    }
}

// MARK: - ============ A股服务 ============
class StockService {
    static let shared = StockService()
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }
    
    // 获取单个股票信息（新浪财经API）
    func fetchStockInfo(code: String) async -> StockInfo? {
        // 新浪股票API：sh=上海，sz=深圳
        let prefix = code.hasPrefix("6") ? "sh" : "sz"
        let urlString = "https://hq.sinajs.cn/list=\(prefix)\(code)"
        
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            
            // 尝试多种编码
            let text: String?
            if let utf8Text = String(data: data, encoding: .utf8), !utf8Text.isEmpty {
                text = utf8Text
            } else if let gbkText = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
                text = gbkText
            } else {
                text = String(data: data, encoding: .ascii)
            }
            
            guard let text = text, !text.isEmpty else { return nil }
            
            // 解析数据：var hq_str_sh600000="浦发银行,12.34,12.50,..."
            let lines = text.components(separatedBy: ";")
            for line in lines {
                if line.contains("hq_str_\(prefix)\(code)") {
                    return parseSinaStockData(line, code: code)
                }
            }
        } catch {
            print("Stock fetch error for \(code): \(error)")
        }
        return nil
    }
    
    /// 按新浪 list 代码拉取（用于指数：sh000001 上证、sz399001 深证、sz399006 创业板）
    func fetchIndexInfo(listCode: String) async -> StockInfo? {
        let urlString = "https://hq.sinajs.cn/list=\(listCode)"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await session.data(for: request)
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
                ?? ""
            let lines = text.components(separatedBy: ";")
            for line in lines {
                if line.contains("hq_str_\(listCode)") {
                    let code = String(listCode.dropFirst(2))
                    return parseSinaStockData(line, code: code)
                }
            }
        } catch {
            print("Index fetch error \(listCode): \(error)")
        }
        return nil
    }
    
    /// 三大指数：上证、深证、创业板（固定顺序）
    func fetchMainIndices() async -> [StockInfo] {
        let listCodes = ["sh000001", "sz399001", "sz399006"]
        var results: [StockInfo] = []
        await withTaskGroup(of: StockInfo?.self) { group in
            for listCode in listCodes {
                group.addTask { await self.fetchIndexInfo(listCode: listCode) }
            }
            for await result in group {
                if let info = result { results.append(info) }
            }
        }
        // 保证顺序：上证、深证、创业板
        let order = ["000001", "399001", "399006"]
        return order.compactMap { code in results.first(where: { $0.code == code }) }
    }
    
    private func parseSinaStockData(_ line: String, code: String) -> StockInfo? {
        let cleanedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let start = cleanedLine.firstIndex(of: "\""),
              let end = cleanedLine.lastIndex(of: "\"") else {
            return nil
        }
        
        let content = String(cleanedLine[cleanedLine.index(after: start)..<end])
        let parts = content.components(separatedBy: ",")
        
        // 新浪股票API格式：名称,今日开盘价,昨日收盘价,当前价,今日最高价,今日最低价,竞买价,竞卖价,成交股数,成交金额,买1数量,买1价格,买2数量,买2价格,...,日期,时间
        guard parts.count > 3 else { return nil }
        
        var stock = StockInfo(code: code, name: parts[0])
        
        // 新浪股票API格式：名称,今日开盘价,昨日收盘价,当前价,今日最高价,今日最低价,竞买价,竞卖价,成交股数,成交金额,...
        // 当前价（索引3）
        var currentPrice: Double? = nil
        var yesterdayPrice: Double? = nil
        
        // 尝试解析当前价（索引3）
        if parts.count > 3 {
            if let price = Double(parts[3]), price > 0 {
                currentPrice = price
                stock.currentPrice = String(format: "%.2f", price)
            } else {
                // 如果索引3不是有效价格，尝试其他位置
                print("Stock \(code): parts[3] = '\(parts[3])' is not a valid price, trying other positions")
            }
        }
        
        // 昨收（索引2）
        if parts.count > 2 {
            if let yp = Double(parts[2]), yp > 0 {
                yesterdayPrice = yp
                stock.yesterdayPrice = String(format: "%.2f", yp)
            }
        }
        
        // 如果当前价还没获取到，尝试从其他位置获取
        if currentPrice == nil && parts.count > 1 {
            // 尝试索引1（开盘价）作为备选
            if let price = Double(parts[1]), price > 0 {
                currentPrice = price
                stock.currentPrice = String(format: "%.2f", price)
            }
        }
        
        // 计算涨跌额和涨跌幅
        if let cp = currentPrice, let yp = yesterdayPrice, yp > 0 {
            let change = cp - yp
            let changePercent = (change / yp) * 100
            let sign = change >= 0 ? "+" : ""
            stock.changeAmount = String(format: "\(sign)%.2f", change)
            stock.changeRate = String(format: "\(sign)%.2f%%", changePercent)
        } else if let cp = currentPrice {
            // 有当前价但没有昨收价，只显示价格
            stock.currentPrice = String(format: "%.2f", cp)
        } else {
            // 无法获取价格，打印调试信息
            print("Stock \(code): Failed to parse price. Parts count: \(parts.count)")
            if parts.count > 0 {
                print("  Name: \(parts[0])")
            }
            if parts.count > 1 {
                print("  Part[1]: \(parts[1])")
            }
            if parts.count > 2 {
                print("  Part[2]: \(parts[2])")
            }
            if parts.count > 3 {
                print("  Part[3]: \(parts[3])")
            }
        }
        
        // 成交量（索引8）
        if parts.count > 8, let vol = Double(parts[8]), vol > 0 {
            if vol >= 10000 {
                stock.volume = String(format: "%.2f万手", vol / 10000)
            } else {
                stock.volume = String(format: "%.0f手", vol)
            }
        }
        
        // 成交额（索引9）
        if parts.count > 9, let amt = Double(parts[9]), amt > 0 {
            if amt >= 100000000 {
                stock.amount = String(format: "%.2f亿", amt / 100000000)
            } else if amt >= 10000 {
                stock.amount = String(format: "%.2f万", amt / 10000)
            } else {
                stock.amount = String(format: "%.0f", amt)
            }
        }
        
        stock.lastUpdate = Date()
        return stock
    }
    
    // 批量获取股票信息
    func fetchAllStocks(codes: [String]) async -> [StockInfo] {
        var results: [StockInfo] = []
        
        await withTaskGroup(of: StockInfo?.self) { group in
            for code in codes {
                group.addTask {
                    return await self.fetchStockInfo(code: code)
                }
            }
            
            for await result in group {
                if let stock = result {
                    results.append(stock)
                }
            }
        }
        
        return results
    }
}

// MARK: - ============ A股存储管理 ============
class StockStorage {
    static let shared = StockStorage()
    
    private let stocksKey = "savedStocks"
    
    private init() {}
    
    var savedStocks: [StockInfo] {
        get {
            guard let data = UserDefaults.standard.data(forKey: stocksKey),
                  let stocks = try? JSONDecoder().decode([StockInfo].self, from: data) else {
                return []
            }
            return stocks
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: stocksKey)
                UserDefaults.standard.synchronize()   // 立即落盘，防止进程被强杀时丢失数据
            }
        }
    }
    
    /// 置顶股票代码（用于状态栏显示）
    var pinnedStockCode: String? {
        get { UserDefaults.standard.string(forKey: "pinnedStockCode") }
        set { UserDefaults.standard.set(newValue, forKey: "pinnedStockCode") }
    }

    func addStock(_ stock: StockInfo) {
        var stocks = savedStocks
        if !stocks.contains(where: { $0.code == stock.code }) {
            stocks.append(stock)
            savedStocks = stocks
        }
    }
    
    func removeStock(code: String) {
        var stocks = savedStocks
        stocks.removeAll { $0.code == code }
        savedStocks = stocks
    }
    
    func updateStock(_ stock: StockInfo) {
        var stocks = savedStocks
        if let index = stocks.firstIndex(where: { $0.code == stock.code }) {
            stocks[index] = stock
            savedStocks = stocks
        }
    }
}

// MARK: - ============ 基金存储管理 ============
class FundStorage {
    static let shared = FundStorage()

    private let fundsKey = "savedFunds"
    private let categoriesKey = "savedCategories"
    private let displayModeKey = "displayMode"  // 悬浮窗当前页签 "gold" or "stock"
    private let statusBarDisplayModeKey = "statusBarDisplayMode"  // 状态栏显示 "gold" or "stock"，与悬浮窗独立

    private init() {}

    /// 状态栏显示模式（仅影响菜单栏显示内容，与悬浮窗页签无关）
    var statusBarDisplayMode: String {
        get { UserDefaults.standard.string(forKey: statusBarDisplayModeKey) ?? "gold" }
        set { UserDefaults.standard.set(newValue, forKey: statusBarDisplayModeKey) }
    }

    // 保存的基金列表
    var savedFunds: [FundInfo] {
        get {
            guard let data = UserDefaults.standard.data(forKey: fundsKey),
                  let funds = try? JSONDecoder().decode([FundInfo].self, from: data) else {
                return []
            }
            return funds
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: fundsKey)
            }
        }
    }

    // 分类列表
    var categories: [FundCategory] {
        get {
            guard let data = UserDefaults.standard.data(forKey: categoriesKey),
                  let cats = try? JSONDecoder().decode([FundCategory].self, from: data) else {
                return [
                    FundCategory(name: "全部"),
                    FundCategory(name: "股票型"),
                    FundCategory(name: "混合型"),
                    FundCategory(name: "债券型"),
                    FundCategory(name: "指数型"),
                    FundCategory(name: "QDII")
                ]
            }
            return cats
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: categoriesKey)
            }
        }
    }

    /// 悬浮窗当前页签（与状态栏显示独立）
    var displayMode: String {
        get { UserDefaults.standard.string(forKey: displayModeKey) ?? "gold" }
        set { UserDefaults.standard.set(newValue, forKey: displayModeKey) }
    }

    func addFund(_ fund: FundInfo) {
        var funds = savedFunds
        if !funds.contains(where: { $0.code == fund.code }) {
            funds.append(fund)
            savedFunds = funds
        }
    }

    func removeFund(code: String) {
        var funds = savedFunds
        funds.removeAll { $0.code == code }
        savedFunds = funds
    }

    func updateFund(_ fund: FundInfo) {
        var funds = savedFunds
        if let index = funds.firstIndex(where: { $0.code == fund.code }) {
            funds[index] = fund
            savedFunds = funds
        }
    }

    func getFundsByCategory(_ categoryName: String) -> [FundInfo] {
        if categoryName == "全部" {
            return savedFunds
        }
        return savedFunds.filter { $0.type == categoryName }
    }
}

// MARK: - ============ 悬浮窗 ============
class FloatingWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.minSize = NSSize(width: 320, height: 200)
    }

    // 允许成为 key window，使输入框可以正常接收键盘事件
    override var canBecomeKey: Bool { return true }

    func positionAtTopRight() {
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.maxX - self.frame.width - 20
            let y = screenRect.maxY - self.frame.height - 20
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

// MARK: - ============ 拖拽缩放手柄 ============
/// 放在悬浮窗右下角，拖拽即可调整窗口大小
class ResizeHandleView: NSView {
    private var dragStartMouse: NSPoint = .zero
    private var dragStartFrame: NSRect  = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func cursorUpdate(with event: NSEvent) {
        // macOS 12.0 没有 resizeUpLeftDownRight，用 openHand 表示可拖拽
        NSCursor.openHand.set()
    }

    /// 画三个对角小圆点，模拟 macOS 原生 resize 指示器
    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor(white: 0.55, alpha: 0.65)
        color.setFill()
        let s: CGFloat = 2.5, gap: CGFloat = 4.0
        let cx = bounds.maxX - 6, cy = bounds.minY + 6
        for i in 0..<3 {
            let x = cx - CGFloat(i) * gap
            let y = cy + CGFloat(i) * gap
            NSBezierPath(ovalIn: NSRect(x: x - s/2, y: y - s/2, width: s, height: s)).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        dragStartMouse = NSEvent.mouseLocation
        dragStartFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let cur = NSEvent.mouseLocation
        let dx = cur.x - dragStartMouse.x
        let dy = cur.y - dragStartMouse.y
        var f = dragStartFrame
        f.size.width  = max(window.minSize.width,  f.width  + dx)
        f.size.height = max(window.minSize.height, f.height - dy)  // dy<0 = 向下拖 = 增高
        f.origin.y    = dragStartFrame.maxY - f.size.height        // 顶边锁定
        window.setFrame(f, display: true)
    }
}

// MARK: - ============ 黄金内容视图 ============
class GoldContentView: NSView {
    private var prices = GoldPrices()
    private var priceLabels: [String: NSTextField] = [:]
    private var changeLabels: [String: NSTextField] = [:]
    private var timeLabel: NSTextField!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        // 背景透明，继承父视图浅色背景

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment   = .centerX
        container.spacing     = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        container.edgeInsets  = NSEdgeInsets(top: 10, left: 0, bottom: 8, right: 0)

        // ── 国内金价 section ─────────────────────────────────
        let domesticTitle = makeSectionHeader("国内金价  元/克")
        container.addArrangedSubview(domesticTitle)
        domesticTitle.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        container.setCustomSpacing(8, after: domesticTitle)

        addPriceRow(to: container, key: "minsheng", name: "民生银行")
        addPriceRow(to: container, key: "icbc",     name: "工商银行")
        addPriceRow(to: container, key: "zheshang", name: "浙商银行")
        container.setCustomSpacing(12, after: container.arrangedSubviews.last!)

        // ── 分隔线 ────────────────────────────────────────────
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 0.82, alpha: 1).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.88).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        container.setCustomSpacing(12, after: sep)

        // ── 国际金价 section ─────────────────────────────────
        let intlTitle = makeSectionHeader("国际金价  美元/盎司")
        container.addArrangedSubview(intlTitle)
        intlTitle.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        container.setCustomSpacing(8, after: intlTitle)

        addPriceRow(to: container, key: "london",  name: "伦敦金")
        addPriceRow(to: container, key: "newyork", name: "纽约金")

        // ── 弹性空白 + 更新时间 ───────────────────────────────
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        container.addArrangedSubview(spacer)

        timeLabel = createLabel("--:--:--", size: 11, bold: false,
                                color: NSColor(white: 0.55, alpha: 1))
        timeLabel.alignment = .center
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(timeLabel)
        timeLabel.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    /// 带左侧彩条的分区标题
    private func makeSectionHeader(_ title: String) -> NSView {
        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(red: 0.18, green: 0.48, blue: 0.92, alpha: 1).cgColor
        bar.layer?.cornerRadius = 1.5
        bar.translatesAutoresizingMaskIntoConstraints = false

        let lbl = createLabel(title, size: 12, bold: true,
                              color: NSColor(white: 0.32, alpha: 1))
        lbl.translatesAutoresizingMaskIntoConstraints = false

        wrapper.addSubview(bar)
        wrapper.addSubview(lbl)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 28),
            bar.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 12),
            bar.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            bar.widthAnchor.constraint(equalToConstant: 3),
            bar.heightAnchor.constraint(equalToConstant: 14),
            lbl.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 6),
            lbl.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])
        return wrapper
    }

    private func createLabel(_ text: String, size: CGFloat, bold: Bool, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.textColor = color
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        return label
    }

    private func addPriceRow(to stack: NSStackView, key: String, name: String) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fillEqually  // 三列等宽，各自居中
        row.spacing = 0

        let nameLabel = createLabel(name, size: 13, bold: false,
                                    color: NSColor(white: 0.38, alpha: 1))
        nameLabel.alignment = .center

        let priceLabel = createLabel("----", size: 15, bold: true,
                                     color: NSColor(red: 0.1, green: 0.25, blue: 0.72, alpha: 1))
        priceLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        priceLabel.alignment = .center
        priceLabels[key] = priceLabel

        let changeLabel = createLabel("", size: 12, bold: false,
                                      color: NSColor(red: 0.82, green: 0.08, blue: 0.08, alpha: 1))
        changeLabel.alignment = .center
        changeLabels[key] = changeLabel

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(priceLabel)
        row.addArrangedSubview(changeLabel)

        row.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }

    func updatePrices(_ prices: GoldPrices) {
        self.prices = prices

        updatePriceDisplay(key: "minsheng", info: prices.minsheng)
        updatePriceDisplay(key: "icbc",     info: prices.icbc)
        updatePriceDisplay(key: "zheshang", info: prices.zheshang)

        updatePriceDisplay(key: "london",   info: prices.london)
        updatePriceDisplay(key: "newyork",  info: prices.newyork)

        if let lastUpdate = prices.lastUpdate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            timeLabel.stringValue = "更新: " + formatter.string(from: lastUpdate)
        }
    }

    private func updatePriceDisplay(key: String, info: PriceInfo) {
        priceLabels[key]?.stringValue = info.price

        if !info.changeRate.isEmpty {
            let arrow = info.isUp ? "▲" : "▼"
            changeLabels[key]?.stringValue = "\(arrow) \(info.changeRate)"
            changeLabels[key]?.textColor = info.isUp
                ? NSColor(red: 0.82, green: 0.08, blue: 0.08, alpha: 1)
                : NSColor(red: 0.06, green: 0.5, blue: 0.15, alpha: 1)
        } else {
            changeLabels[key]?.stringValue = ""
        }
    }
}

// MARK: - ============ 基金内容视图 ============
class FundContentView: NSView, NSTableViewDelegate, NSTableViewDataSource {
    private var allFunds: [FundInfo] = []  // 存储所有基金数据
    private var displayFunds: [FundInfo] = []  // 用于显示的基金列表
    private var categories: [FundCategory] = []
    private var selectedCategory: String = "全部"
    private var timeLabel: NSTextField!
    private var tableView: NSTableView!
    private var categorySegment: NSSegmentedControl!
    private weak var appDelegate: AppDelegate?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
        loadSavedData()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        loadSavedData()
    }

    func setAppDelegate(_ delegate: AppDelegate) {
        self.appDelegate = delegate
    }

    private func setupUI() {
        wantsLayer = true
        // 子视图不重复设置背景，由 MainContentView 统一控制

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4
        container.translatesAutoresizingMaskIntoConstraints = false
        container.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

        // Header
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 6

        let titleLabel = NSTextField(labelWithString: "我的基金")
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor(white: 0.85, alpha: 1)

        let addButton = NSButton()
        addButton.bezelStyle = .inline
        addButton.title = "＋"
        addButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        addButton.controlSize = .small
        addButton.target = self
        addButton.action = #selector(showAddFundDialog)
        addButton.contentTintColor = NSColor.systemBlue
        addButton.wantsLayer = true
        addButton.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        addButton.layer?.cornerRadius = 5

        let removeButton = NSButton()
        removeButton.bezelStyle = .inline
        removeButton.title = "－"
        removeButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        removeButton.controlSize = .small
        removeButton.target = self
        removeButton.action = #selector(removeSelectedFund)
        removeButton.contentTintColor = NSColor(white: 0.6, alpha: 1)
        removeButton.wantsLayer = true
        removeButton.layer?.backgroundColor = NSColor(white: 0.4, alpha: 0.3).cgColor
        removeButton.layer?.cornerRadius = 5

        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(NSView()) // spacer
        headerStack.addArrangedSubview(addButton)
        headerStack.addArrangedSubview(removeButton)

        container.addArrangedSubview(headerStack)

        // Category segment
        categorySegment = NSSegmentedControl()
        categorySegment.target = self
        categorySegment.action = #selector(categoryChanged(_:))
        categorySegment.trackingMode = .selectOne
        categorySegment.controlSize = .small
        container.addArrangedSubview(categorySegment)

        // Table view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.selectionHighlightStyle = .regular

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("fundColumn"))
        column.width = 320
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // 让 scrollView 弹性填满剩余高度
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        container.addArrangedSubview(scrollView)

        // Time label
        timeLabel = NSTextField(labelWithString: "--:--:--")
        timeLabel.font = NSFont.systemFont(ofSize: 10)
        timeLabel.textColor = NSColor.lightGray
        timeLabel.alignment = .center
        container.addArrangedSubview(timeLabel)

        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func loadSavedData() {
        categories = FundStorage.shared.categories
        allFunds = FundStorage.shared.savedFunds
        updateCategorySegment()
        refreshDisplay()
    }

    private func updateCategorySegment() {
        categorySegment.segmentCount = min(categories.count, 5)
        for i in 0..<min(categories.count, 5) {
            categorySegment.setLabel(categories[i].name, forSegment: i)
            if categories[i].name == selectedCategory {
                categorySegment.selectedSegment = i
            }
        }
    }

    @objc private func categoryChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        if index < categories.count {
            selectedCategory = categories[index].name
            refreshDisplay()
        }
    }

    @objc private func showAddFundDialog() {
        let alert = NSAlert()
        alert.messageText = "添加基金"
        alert.informativeText = "请输入6位基金代码\n例如：000001（华夏成长）、110022（易方达消费行业）"
        alert.alertStyle = .informational

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputField.placeholderString = "如: 000001"
        alert.accessoryView = inputField

        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")

        alert.window.makeFirstResponder(inputField)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let code = inputField.stringValue.trimmingCharacters(in: .whitespaces)
            if !code.isEmpty {
                // 验证基金代码格式（6位数字）
                if code.count == 6 && code.allSatisfy({ $0.isNumber }) {
                Task { await addFund(code: code) }
                } else {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "基金代码格式错误"
                    errorAlert.informativeText = "基金代码必须是6位数字，例如：000001"
                    errorAlert.alertStyle = .warning
                    errorAlert.addButton(withTitle: "好")
                    errorAlert.runModal()
                }
            }
        }
    }

    private func addFund(code: String) async {
        if let fund = await FundService.shared.fetchFundInfo(code: code) {
            await MainActor.run {
                FundStorage.shared.addFund(fund)
                self.allFunds = FundStorage.shared.savedFunds
                self.refreshDisplay()
                
                // 通知 AppDelegate 立即刷新基金数据
                if let delegate = self.appDelegate {
                    Task {
                        await delegate.refreshFunds()
                    }
                }
                
                // 显示成功提示
                let successAlert = NSAlert()
                successAlert.messageText = "添加成功"
                successAlert.informativeText = "基金 \(fund.name.isEmpty ? code : fund.name) 已添加\n当前净值: \(fund.estimatedValue)\n涨跌幅: \(fund.estimatedRate)%"
                successAlert.alertStyle = .informational
                successAlert.addButton(withTitle: "好")
                successAlert.runModal()
            }
        } else {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "添加失败"
                alert.informativeText = "无法获取基金 \(code) 的信息，请检查代码是否正确。\n\n提示：\n1. 基金代码必须是6位数字\n2. 确保网络连接正常\n3. 常见基金代码示例：\n   - 000001（华夏成长）\n   - 110022（易方达消费行业）\n   - 161725（招商中证白酒）"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
        }
    }

    @objc private func removeSelectedFund() {
        let selectedRow = tableView.selectedRow
        if selectedRow >= 0 && selectedRow < displayFunds.count {
            let fund = displayFunds[selectedRow]
            FundStorage.shared.removeFund(code: fund.code)
            allFunds = FundStorage.shared.savedFunds
            refreshDisplay()
        }
    }

    func updateFunds(_ newFunds: [FundInfo]) {
        self.allFunds = newFunds
        FundStorage.shared.savedFunds = newFunds
        refreshDisplay()
    }

    private func refreshDisplay() {
        // 根据选择的分类筛选基金
        if selectedCategory == "全部" {
            displayFunds = allFunds
        } else {
            displayFunds = allFunds.filter { $0.type == selectedCategory }
        }

        // 更新表格显示
        tableView.reloadData()

        // 更新时间标签
        if let lastUpdate = displayFunds.first?.lastUpdate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            timeLabel.stringValue = "更新: " + formatter.string(from: lastUpdate)
        } else if !displayFunds.isEmpty {
            timeLabel.stringValue = "点击 + 添加基金"
        } else {
            timeLabel.stringValue = "暂无基金数据"
        }
    }

    // MARK: - NSTableViewDataSource
    func numberOfRows(in tableView: NSTableView) -> Int {
        return displayFunds.count
    }

    // MARK: - NSTableViewDelegate
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayFunds.count else { return nil }
        let fund = displayFunds[row]

        let cellView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 28))

        // Name label
        let nameLabel = NSTextField(frame: NSRect(x: 0, y: 6, width: 120, height: 16))
        nameLabel.stringValue = fund.name.isEmpty ? fund.code : fund.name
        nameLabel.font = NSFont.systemFont(ofSize: 11)
        nameLabel.textColor = NSColor(white: 0.75, alpha: 1)
        nameLabel.backgroundColor = .clear
        nameLabel.isBezeled = false
        nameLabel.isEditable = false
        cellView.addSubview(nameLabel)

        // Value label
        let valueLabel = NSTextField(frame: NSRect(x: 125, y: 6, width: 82, height: 16))
        valueLabel.stringValue = fund.estimatedValue
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.textColor = NSColor.systemYellow
        valueLabel.backgroundColor = .clear
        valueLabel.isBezeled = false
        valueLabel.isEditable = false
        valueLabel.alignment = .right
        cellView.addSubview(valueLabel)

        // Rate label
        let rateLabel = NSTextField(frame: NSRect(x: 212, y: 6, width: 104, height: 16))
        let isUp = fund.isUp
        let arrow = isUp ? "▲" : "▼"
        rateLabel.stringValue = "\(arrow) \(fund.estimatedRate)%"
        rateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        rateLabel.textColor = isUp ? NSColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1) : NSColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1)
        rateLabel.backgroundColor = .clear
        rateLabel.isBezeled = false
        rateLabel.isEditable = false
        rateLabel.alignment = .right
        cellView.addSubview(rateLabel)

        return cellView
    }
}

// MARK: - 股票表头（内嵌在 NSTableView，与 cell 共享同一列宽，对齐有保证）
private class StockTableHeaderView: NSTableHeaderView {
    /// 0 = 无排序  1 = 降序(大→小)  -1 = 升序(小→大)
    var rateSortState: Int = 0 { didSet { needsDisplay = true } }
    /// 点击涨幅列时触发
    var onRateSortTapped: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let nW = bounds.width * StockRowView.namePct
        let pW = bounds.width * StockRowView.pricePct
        if pt.x > nW + pW { onRateSortTapped?() }
        else { super.mouseDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        let nW = w * StockRowView.namePct
        let pW = w * StockRowView.pricePct
        let rW = w - nW - pW

        let activeColor  = NSColor(red: 0.18, green: 0.48, blue: 0.92, alpha: 1)
        let isSorting    = rateSortState != 0

        // ── 背景：平铺浅蓝灰，激活列用淡蓝色高亮 ──────────────
        NSColor(red: 0.91, green: 0.93, blue: 0.96, alpha: 1).setFill()
        bounds.fill()
        if isSorting {
            NSColor(red: 0.18, green: 0.48, blue: 0.92, alpha: 0.07).setFill()
            NSRect(x: nW + pW, y: 0, width: rW, height: h).fill()
        }

        // ── 顶部 & 底部分隔线 ─────────────────────────────────
        NSColor(white: 0.78, alpha: 1).setFill()
        NSRect(x: 0, y: h - 0.5, width: w, height: 0.5).fill()
        NSRect(x: 0, y: 0,       width: w, height: 0.5).fill()

        // ── 列间竖线 ──────────────────────────────────────────
        NSColor(white: 0.80, alpha: 0.7).setFill()
        NSRect(x: nW,      y: h * 0.2, width: 0.5, height: h * 0.6).fill()
        NSRect(x: nW + pW, y: h * 0.2, width: 0.5, height: h * 0.6).fill()

        // ── 文字通用辅助 ──────────────────────────────────────
        let normalFont   = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let normalColor  = NSColor(red: 0.25, green: 0.28, blue: 0.35, alpha: 1)
        func centerAttrs(_ color: NSColor, _ font: NSFont = normalFont)
                -> [NSAttributedString.Key: Any] {
            let p = NSMutableParagraphStyle(); p.alignment = .center
            return [.font: font, .foregroundColor: color, .paragraphStyle: p]
        }

        // ── 名称/代码 & 最新 ──────────────────────────────────
        let pad: CGFloat = 8
        NSAttributedString(string: "名称/代码", attributes: centerAttrs(normalColor))
            .draw(in: NSRect(x: pad,       y: (h-13)/2, width: nW - pad * 2, height: 13))
        NSAttributedString(string: "最新", attributes: centerAttrs(normalColor))
            .draw(in: NSRect(x: nW + pad,  y: (h-13)/2, width: pW - pad * 2, height: 13))

        // ── 涨幅列（带排序指示）────────────────────────────────
        let rateStr = NSMutableAttributedString()
        if !isSorting {
            rateStr.append(NSAttributedString(
                string: "涨幅 ",
                attributes: centerAttrs(normalColor)))
            rateStr.append(NSAttributedString(
                string: "⇅",
                attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .regular),
                             .foregroundColor: NSColor(white: 0.55, alpha: 1)]))
            let p = NSMutableParagraphStyle(); p.alignment = .center
            rateStr.addAttribute(.paragraphStyle, value: p,
                                 range: NSRange(location: 0, length: rateStr.length))
        } else {
            let arrow = rateSortState == 1 ? " ↓" : " ↑"
            rateStr.append(NSAttributedString(
                string: "涨幅\(arrow)",
                attributes: centerAttrs(activeColor,
                    NSFont.systemFont(ofSize: 11, weight: .bold))))
        }
        rateStr.draw(in: NSRect(x: nW + pW + pad, y: (h - 14) / 2, width: rW - pad * 2, height: 14))

        // ── 激活列底部蓝色指示条 ──────────────────────────────
        if isSorting {
            activeColor.setFill()
            NSRect(x: nW + pW, y: 0, width: rW, height: 2).fill()
        }
    }
}

// MARK: - 股票行视图（layout 响应实际列宽，确保与列头对齐）
private class StockRowView: NSView {
    private let nameLabel  = NSTextField()   // "名称  代码" 单行
    private let valueLabel = NSTextField()
    private let rateLabel  = NSTextField()
    private let sepLine    = NSView()

    // 与列头保持一致的比例常量
    static let namePct:  CGFloat = 0.40
    static let pricePct: CGFloat = 0.30

    override init(frame: NSRect) { super.init(frame: frame); buildViews() }
    required init?(coder: NSCoder) { super.init(coder: coder); buildViews() }

    private func buildViews() {
        for lbl in [nameLabel, valueLabel, rateLabel] {
            lbl.isBezeled = false; lbl.isEditable = false; lbl.drawsBackground = false
            addSubview(lbl)
        }
        sepLine.wantsLayer = true
        sepLine.layer?.backgroundColor = NSColor(white: 0.89, alpha: 1).cgColor
        addSubview(sepLine)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let nW = w * Self.namePct
        let pW = w * Self.pricePct
        let rW = w - nW - pW
        nameLabel.frame  = NSRect(x: 0,       y: (h - 20)/2, width: nW,  height: 20)
        valueLabel.frame = NSRect(x: nW,      y: (h - 22)/2, width: pW,  height: 22)
        rateLabel.frame  = NSRect(x: nW + pW, y: (h - 22)/2, width: rW,  height: 22)
        sepLine.frame    = NSRect(x: 0, y: 0, width: w, height: 0.5)
    }

    func configure(with stock: StockInfo, isPinned: Bool = false) {
        let rateRaw = stock.changeRate
        let hasRate = !rateRaw.isEmpty && rateRaw != "--"
        let upColor = NSColor(red: 0.88, green: 0.10, blue: 0.10, alpha: 1) // 涨：中国红
        let dnColor = NSColor(red: 0.00, green: 0.65, blue: 0.22, alpha: 1) // 跌：中国绿
        let flatColor = NSColor(white: 0.15, alpha: 1) // 平：黑色
        let accent: NSColor = hasRate
            ? (stock.isUp ? upColor : (stock.isDown ? dnColor : flatColor))
            : NSColor(white: 0.3, alpha: 1)

        // 名称 + 代码 合并为一行，用 AttributedString 双色显示
        let displayName = stock.name.isEmpty ? stock.code : stock.name
        let combinedStr = NSMutableAttributedString()

        // 置顶图钉
        if isPinned {
            combinedStr.append(NSAttributedString(
                string: "📌 ",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ))
        }
        combinedStr.append(NSAttributedString(
            string: displayName,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor(white: 0.08, alpha: 1)
            ]
        ))
        if !stock.name.isEmpty {
            combinedStr.append(NSAttributedString(
                string: "  \(stock.code)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor(white: 0.55, alpha: 1)
                ]
            ))
        }
        let nameStyle = NSMutableParagraphStyle(); nameStyle.alignment = .center
        combinedStr.addAttribute(.paragraphStyle, value: nameStyle,
                                 range: NSRange(location: 0, length: combinedStr.length))
        nameLabel.attributedStringValue = combinedStr

        let priceText = stock.currentPrice.isEmpty || stock.currentPrice == "--" ? "--" : stock.currentPrice
        valueLabel.stringValue = priceText
        valueLabel.font        = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        valueLabel.textColor   = accent
        valueLabel.alignment   = .center

        if hasRate {
            var r = rateRaw
            if !r.hasPrefix("+") && !r.hasPrefix("-") {
                r = stock.isUp ? "+" + r : r // 涨加 +，平/跌不加
            }
            if !r.hasSuffix("%") { r += "%" }
            rateLabel.stringValue = r
            rateLabel.textColor   = accent
        } else {
            rateLabel.stringValue = "--"
            rateLabel.textColor   = NSColor(white: 0.6, alpha: 1)
        }
        rateLabel.font      = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        rateLabel.alignment = .center

        needsLayout = true
    }
}

// MARK: - ============ A股内容视图 ============

class StockContentView: NSView, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate, NSMenuDelegate {
    private var allStocks: [StockInfo] = []
    private var displayStocks: [StockInfo] = []
    private var timeLabel: NSTextField!
    private var tableView: NSTableView!
    private weak var appDelegate: AppDelegate?

    /// 0 = 原始顺序  1 = 涨幅降序  -1 = 涨幅升序
    private var rateSortState: Int = 0
    private var headerView: StockTableHeaderView?
    private var scrollView: NSScrollView!

    /// 三大指数区域（上证、深证、创业板）
    private var indicesContainer: NSView!
    private var indexNameLabels: [NSTextField] = []
    private var indexValueLabels: [NSTextField] = []
    private var indexChangeLabels: [NSTextField] = []

    // 内联输入条
    private var inputBar: NSView!
    private var inputField: NSTextField!
    private var inputBarHeightConstraint: NSLayoutConstraint!
    private var scrollTopConstraint: NSLayoutConstraint!
    private var scrollTopWithInputConstraint: NSLayoutConstraint!
    // 搜索候选
    private var suggestionBox: NSView!
    private var suggestions: [(name: String, code: String)] = []
    private var searchTask: Task<Void, Never>?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
        loadSavedData()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        loadSavedData()
    }
    
    func setAppDelegate(_ delegate: AppDelegate) {
        self.appDelegate = delegate
    }
    
    private func setupUI() {
        wantsLayer = true

        // ── 三大指数（顶部横排）────────────────────────────
        let indexNames = ["上证指数", "深证成指", "创业板指"]
        indicesContainer = NSView()
        indicesContainer.translatesAutoresizingMaskIntoConstraints = false
        let indicesStack = NSStackView(views: [])
        indicesStack.orientation = .horizontal
        indicesStack.distribution = .fillEqually
        indicesStack.spacing = 8
        indicesStack.translatesAutoresizingMaskIntoConstraints = false
        for name in indexNames {
            let block = NSView()
            block.translatesAutoresizingMaskIntoConstraints = false
            let nameLabel = NSTextField(labelWithString: name)
            nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            nameLabel.textColor = NSColor(white: 0.15, alpha: 1)
            nameLabel.alignment = .center
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            let valueLabel = NSTextField(labelWithString: "--")
            valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
            valueLabel.textColor = NSColor(white: 0.5, alpha: 1)
            valueLabel.alignment = .center
            valueLabel.translatesAutoresizingMaskIntoConstraints = false
            let changeLabel = NSTextField(labelWithString: "-- --%")
            changeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            changeLabel.textColor = NSColor(white: 0.5, alpha: 1)
            changeLabel.alignment = .center
            changeLabel.translatesAutoresizingMaskIntoConstraints = false
            let colStack = NSStackView(views: [nameLabel, valueLabel, changeLabel])
            colStack.orientation = .vertical
            colStack.alignment = .centerX
            colStack.spacing = 2
            colStack.translatesAutoresizingMaskIntoConstraints = false
            block.addSubview(colStack)
            NSLayoutConstraint.activate([
                colStack.centerXAnchor.constraint(equalTo: block.centerXAnchor),
                colStack.centerYAnchor.constraint(equalTo: block.centerYAnchor),
            ])
            indicesStack.addArrangedSubview(block)
            indexNameLabels.append(nameLabel)
            indexValueLabels.append(valueLabel)
            indexChangeLabels.append(changeLabel)
        }
        indicesContainer.addSubview(indicesStack)
        NSLayoutConstraint.activate([
            indicesStack.topAnchor.constraint(equalTo: indicesContainer.topAnchor),
            indicesStack.leadingAnchor.constraint(equalTo: indicesContainer.leadingAnchor),
            indicesStack.trailingAnchor.constraint(equalTo: indicesContainer.trailingAnchor),
            indicesStack.bottomAnchor.constraint(equalTo: indicesContainer.bottomAnchor),
        ])

        // ── Header ──────────────────────────────────────
        let titleLabel = NSTextField(labelWithString: "自选")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = NSColor(white: 0.1, alpha: 1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton()
        addButton.bezelStyle = .inline
        addButton.title = "+ 添加"
        addButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        addButton.controlSize = .regular
        addButton.target = self
        addButton.action = #selector(showAddStockDialog)
        addButton.contentTintColor = NSColor(red: 0.9, green: 0.18, blue: 0.18, alpha: 1)
        addButton.wantsLayer = true
        addButton.layer?.backgroundColor = NSColor(red: 0.9, green: 0.18, blue: 0.18, alpha: 0.1).cgColor
        addButton.layer?.cornerRadius = 5
        addButton.translatesAutoresizingMaskIntoConstraints = false

        let removeButton = NSButton()
        removeButton.bezelStyle = .inline
        removeButton.title = "删除"
        removeButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        removeButton.controlSize = .regular
        removeButton.target = self
        removeButton.action = #selector(removeSelectedStock)
        removeButton.contentTintColor = NSColor(white: 0.45, alpha: 1)
        removeButton.wantsLayer = true
        removeButton.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.1).cgColor
        removeButton.layer?.cornerRadius = 5
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        // ── TableView（可滚动，多只自选时显示垂直滚动条）────────────────
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.autohidesScrollers = true

        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        // 用自定义 header view：与 cell 共享同一列宽，对齐有物理保证
        let hv = StockTableHeaderView()
        hv.onRateSortTapped = { [weak self] in self?.toggleRateSort() }
        headerView = hv
        tableView.headerView = hv
        tableView.backgroundColor = .clear
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("stockColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        scrollView.documentView = tableView
        // 表头置于 contentView 之上，否则会被 clipView 挡住导致「涨幅」点击无效
        if let header = tableView.headerView {
            scrollView.addSubview(header, positioned: .above, relativeTo: scrollView.contentView)
        }

        // 右键菜单（置顶）
        let contextMenu = NSMenu()
        contextMenu.delegate = self
        tableView.menu = contextMenu

        // ── TimeLabel ────────────────────────────────────
        timeLabel = NSTextField(labelWithString: "--:--:--")
        timeLabel.font = NSFont.systemFont(ofSize: 11)
        timeLabel.textColor = NSColor(white: 0.55, alpha: 1)
        timeLabel.alignment = .center
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        // ── 内联输入条 ───────────────────────────────────
        inputBar = NSView()
        inputBar.wantsLayer = true
        inputBar.layer?.backgroundColor = NSColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 1).cgColor
        inputBar.layer?.cornerRadius = 7
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.alphaValue = 0
        inputBar.isHidden = true

        inputField = NSTextField()
        inputField.placeholderString = "输入代码（如 600）或名称"
        inputField.font = NSFont.systemFont(ofSize: 12)
        inputField.textColor = NSColor(white: 0.15, alpha: 1)
        inputField.backgroundColor = .white
        inputField.isBezeled = true
        inputField.bezelStyle = .roundedBezel
        inputField.focusRingType = .none
        inputField.delegate = self
        inputField.translatesAutoresizingMaskIntoConstraints = false

        let confirmBtn = NSButton()
        confirmBtn.bezelStyle = .inline
        confirmBtn.title = "✓"
        confirmBtn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        confirmBtn.contentTintColor = NSColor(red: 0.06, green: 0.5, blue: 0.15, alpha: 1)
        confirmBtn.wantsLayer = true
        confirmBtn.layer?.backgroundColor = NSColor(red: 0.06, green: 0.5, blue: 0.15, alpha: 0.12).cgColor
        confirmBtn.layer?.cornerRadius = 5
        confirmBtn.target = self
        confirmBtn.action = #selector(confirmAddStock)
        confirmBtn.translatesAutoresizingMaskIntoConstraints = false

        let cancelBtn = NSButton()
        cancelBtn.bezelStyle = .inline
        cancelBtn.title = "✕"
        cancelBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        cancelBtn.contentTintColor = NSColor(white: 0.45, alpha: 1)
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.10).cgColor
        cancelBtn.layer?.cornerRadius = 5
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelAddInput)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        inputBar.addSubview(inputField)
        inputBar.addSubview(confirmBtn)
        inputBar.addSubview(cancelBtn)
        NSLayoutConstraint.activate([
            cancelBtn.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -6),
            cancelBtn.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            cancelBtn.widthAnchor.constraint(equalToConstant: 26),
            cancelBtn.heightAnchor.constraint(equalToConstant: 22),

            confirmBtn.trailingAnchor.constraint(equalTo: cancelBtn.leadingAnchor, constant: -4),
            confirmBtn.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            confirmBtn.widthAnchor.constraint(equalToConstant: 26),
            confirmBtn.heightAnchor.constraint(equalToConstant: 22),

            inputField.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 6),
            inputField.trailingAnchor.constraint(equalTo: confirmBtn.leadingAnchor, constant: -6),
            inputField.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            inputField.heightAnchor.constraint(equalToConstant: 24),
        ])

        // ── 搜索候选下拉框（最后加，z-order 最高）─────────
        suggestionBox = NSView()
        suggestionBox.wantsLayer = true
        suggestionBox.layer?.backgroundColor = NSColor.white.cgColor
        suggestionBox.layer?.cornerRadius = 8
        suggestionBox.layer?.borderWidth = 0.5
        suggestionBox.layer?.borderColor = NSColor(white: 0.78, alpha: 1).cgColor
        suggestionBox.layer?.shadowOpacity = 0.12
        suggestionBox.layer?.shadowOffset = CGSize(width: 0, height: -3)
        suggestionBox.layer?.shadowRadius = 6
        suggestionBox.isHidden = true
        suggestionBox.translatesAutoresizingMaskIntoConstraints = false

        addSubview(indicesContainer)
        addSubview(titleLabel)
        addSubview(addButton)
        addSubview(removeButton)
        addSubview(inputBar)
        addSubview(scrollView)
        addSubview(timeLabel)
        addSubview(suggestionBox) // 最后加 = 最上层

        // scrollView 两套顶部约束（含/不含 inputBar）
        scrollTopConstraint = scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6)
        scrollTopWithInputConstraint = scrollView.topAnchor.constraint(equalTo: inputBar.bottomAnchor, constant: 4)
        scrollTopConstraint.isActive = true

        NSLayoutConstraint.activate([
            indicesContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            indicesContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            indicesContainer.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            indicesContainer.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: indicesContainer.bottomAnchor, constant: 12),

            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            removeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 42),
            removeButton.heightAnchor.constraint(equalToConstant: 22),

            addButton.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -6),
            addButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 52),
            addButton.heightAnchor.constraint(equalToConstant: 22),

            // inputBar 紧贴 title 下方，全宽
            inputBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            inputBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            inputBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            inputBar.heightAnchor.constraint(equalToConstant: 36),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: timeLabel.topAnchor, constant: -2),

            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            timeLabel.heightAnchor.constraint(equalToConstant: 14),

            // suggestionBox 紧贴 inputBar 下方，全宽
            suggestionBox.topAnchor.constraint(equalTo: inputBar.bottomAnchor, constant: 2),
            suggestionBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            suggestionBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }
    
    private func loadSavedData() {
        allStocks = StockStorage.shared.savedStocks
        refreshDisplay()
    }
    
    @objc private func showAddStockDialog() {
        guard inputBar.isHidden else {
            // 已展开则收起
            hideInputBar()
            return
        }
        inputField.stringValue = ""
        inputBar.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            inputBar.animator().alphaValue = 1
        }
        scrollTopConstraint.isActive = false
        scrollTopWithInputConstraint.isActive = true
        layoutSubtreeIfNeeded()
        window?.makeKey()
        window?.makeFirstResponder(inputField)
    }

    private func hideInputBar() {
        hideSuggestions()
        scrollTopWithInputConstraint.isActive = false
        scrollTopConstraint.isActive = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            inputBar.animator().alphaValue = 0
        }, completionHandler: {
            self.inputBar.isHidden = true
        })
        layoutSubtreeIfNeeded()
    }

    // MARK: - 股票名称模糊搜索 & 候选下拉

    private func searchStocksForSuggestion(query: String) async {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        // 新浪 suggest：type=11(沪A) + 12(深A)
        let urlString = "http://suggest3.sinajs.cn/suggest/type=11,12&key=\(encoded)"
        guard let url = URL(string: urlString) else { return }
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: request)
            let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: String.Encoding(rawValue: 0x80000632))
                ?? ""
            print("[Suggest] query=\(query) raw=\(raw.prefix(300))")
            let results = parseSinaSuggestion(raw)
            print("[Suggest] parsed=\(results)")
            await MainActor.run {
                if Task.isCancelled { return }
                if results.isEmpty {
                    self.hideSuggestions()
                } else {
                    self.showSuggestions(results)
                }
            }
        } catch {
            // 网络失败静默忽略
        }
    }

    /// 解析新浪 suggest 响应
    /// 按名称搜索: var suggestvalue="贵州茅台,11,600519,...;"  parts[0]=名称  parts[2]=代码
    /// 按代码搜索: var suggestvalue="600519,11,600519,贵州茅台,...;"  parts[0]=代码  parts[3]=名称
    private func parseSinaSuggestion(_ raw: String) -> [(name: String, code: String)] {
        guard let q1 = raw.firstIndex(of: "\""),
              let q2 = raw.lastIndex(of: "\""),
              q1 < q2 else { return [] }
        let content = String(raw[raw.index(after: q1)..<q2])
        var results: [(name: String, code: String)] = []
        for item in content.split(separator: ";") {
            let parts = item.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let field0 = String(parts[0])
            let code   = String(parts[2])
            guard code.count == 6, code.allSatisfy({ $0.isNumber }) else { continue }
            // 代码搜索时 parts[0] = "sh600519" / "sz000001"（市场前缀+代码）
            // 名称搜索时 parts[0] = "贵州茅台"（中文名）
            // 判断：若 parts[0] 不含中文，则认为是代码搜索，遍历所有字段取第一个含中文的部分作为名称
            let hasChinese = field0.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
            let name: String
            if hasChinese {
                name = field0
            } else {
                // 代码搜索返回格式如: sh600111,11,600111,sh600111,北方稀土,...
                // parts[3] 仍是市场+代码，中文名在 parts[4] 及之后，遍历找第一个含中文的字段
                let chinesePart = parts.first { part in
                    part.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
                }
                name = chinesePart.map(String.init) ?? code
            }
            guard !name.isEmpty else { continue }
            results.append((name: name, code: code))
            if results.count >= 8 { break }
        }
        return results
    }

    private func showSuggestions(_ items: [(name: String, code: String)]) {
        // 清空旧条目
        suggestionBox.subviews.forEach { $0.removeFromSuperview() }
        self.suggestions = items

        var lastAnchor: NSLayoutYAxisAnchor = suggestionBox.topAnchor
        var lastConstant: CGFloat = 6

        for (i, item) in items.enumerated() {
            let btn = NSButton()
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.target = self
            btn.action = #selector(suggestionItemTapped(_:))
            btn.tag = i
            btn.alignment = .left
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 5
            btn.translatesAutoresizingMaskIntoConstraints = false

            // 构造富文本：中文名称（加粗） + 灰色代码
            let attrStr = NSMutableAttributedString()
            attrStr.append(NSAttributedString(string: "  \(item.name)", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor(white: 0.1, alpha: 1)
            ]))
            attrStr.append(NSAttributedString(string: "  (\(item.code))", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(white: 0.55, alpha: 1)
            ]))
            btn.attributedTitle = attrStr

            // 悬停背景（利用 trackingArea）
            btn.addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: btn, userInfo: nil))

            suggestionBox.addSubview(btn)
            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: lastAnchor, constant: lastConstant),
                btn.leadingAnchor.constraint(equalTo: suggestionBox.leadingAnchor, constant: 4),
                btn.trailingAnchor.constraint(equalTo: suggestionBox.trailingAnchor, constant: -4),
                btn.heightAnchor.constraint(equalToConstant: 28),
            ])
            lastAnchor = btn.bottomAnchor
            lastConstant = 0

            // 分隔线（非最后一项）
            if i < items.count - 1 {
                let sep = NSView()
                sep.wantsLayer = true
                sep.layer?.backgroundColor = NSColor(white: 0.88, alpha: 1).cgColor
                sep.translatesAutoresizingMaskIntoConstraints = false
                suggestionBox.addSubview(sep)
                NSLayoutConstraint.activate([
                    sep.topAnchor.constraint(equalTo: btn.bottomAnchor),
                    sep.leadingAnchor.constraint(equalTo: suggestionBox.leadingAnchor, constant: 8),
                    sep.trailingAnchor.constraint(equalTo: suggestionBox.trailingAnchor, constant: -8),
                    sep.heightAnchor.constraint(equalToConstant: 0.5),
                ])
                lastAnchor = sep.bottomAnchor
            }
        }
        // 让 box 高度由内容撑开
        lastAnchor.constraint(equalTo: suggestionBox.bottomAnchor, constant: -6).isActive = true

        suggestionBox.isHidden = false
        // 强制重新布局使 shadow 正确
        suggestionBox.needsLayout = true
        suggestionBox.layoutSubtreeIfNeeded()
    }

    @objc private func suggestionItemTapped(_ sender: NSButton) {
        let idx = sender.tag
        guard idx < suggestions.count else { return }
        let item = suggestions[idx]
        hideSuggestions()
        inputField.stringValue = item.code
        // 短暂展示选中的名称
        timeLabel.stringValue = "已选：\(item.name)（\(item.code)）"
        // 自动确认
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.confirmAddStock()
        }
    }

    private func hideSuggestions() {
        suggestionBox?.isHidden = true
        // 清空约束以便下次重建
        suggestionBox?.subviews.forEach { $0.removeFromSuperview() }
        suggestions = []
        searchTask?.cancel()
    }

    @objc private func confirmAddStock() {
        let code = inputField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { hideInputBar(); return }
        guard code.count == 6 && code.allSatisfy({ $0.isNumber }) else {
            showTip("代码须为6位数字，如 600519")
            inputField.selectText(nil)
            return
        }
        hideInputBar()
        showTip("正在查询 \(code)...")
        Task { await addStock(code: code) }
    }

    @objc private func cancelAddInput() {
        hideInputBar()
    }

    // NSTextFieldDelegate — 按 Enter 确认 / Esc 取消
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            // 如果有候选项高亮，选中它；否则直接确认
            confirmAddStock()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            if !suggestionBox.isHidden {
                hideSuggestions()
            } else {
                cancelAddInput()
            }
            return true
        }
        return false
    }

    // 输入内容变化时实时搜索（名称/拼音/代码均支持）
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === inputField else { return }
        let text = inputField.stringValue.trimmingCharacters(in: .whitespaces)
        searchTask?.cancel()
        guard text.count >= 2 else {
            hideSuggestions()
            return
        }
        // 数字（代码）用 200ms 防抖，文字/拼音用 300ms
        let delay: UInt64 = text.allSatisfy({ $0.isNumber }) ? 200_000_000 : 300_000_000
        searchTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await searchStocksForSuggestion(query: text)
        }
    }

    private func showTip(_ msg: String) {
        timeLabel.stringValue = msg
        // 3 秒后自动刷回正常状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.refreshDisplay()
        }
    }
    
    private func addStock(code: String) async {
        if let stock = await StockService.shared.fetchStockInfo(code: code) {
            await MainActor.run {
                StockStorage.shared.addStock(stock)
                self.allStocks = StockStorage.shared.savedStocks
                self.refreshDisplay()
                let name = stock.name.isEmpty ? code : stock.name
                showTip("✓ 已添加 \(name)  \(stock.currentPrice)  \(stock.changeRate)")
                if let delegate = self.appDelegate {
                    Task { await delegate.refreshStocks() }
                }
            }
        } else {
            await MainActor.run {
                showTip("✗ 未找到 \(code)，请确认代码正确")
            }
        }
    }
    
    @objc private func removeSelectedStock() {
        let selectedRow = tableView.selectedRow
        if selectedRow >= 0 && selectedRow < displayStocks.count {
            let stock = displayStocks[selectedRow]
            StockStorage.shared.removeStock(code: stock.code)
            allStocks = StockStorage.shared.savedStocks
            refreshDisplay()
        }
    }
    
    func updateStocks(_ newStocks: [StockInfo]) {
        self.allStocks = newStocks
        refreshDisplay()
    }

    /// 更新三大指数展示（上证、深证、创业板，顺序固定）
    func updateIndices(_ indices: [StockInfo]) {
        let upColor = NSColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 1)
        let dnColor = NSColor(red: 0.06, green: 0.55, blue: 0.25, alpha: 1)
        let flatColor = NSColor(white: 0.45, alpha: 1)
        for (i, label) in indexValueLabels.enumerated() {
            guard i < indices.count else {
                label.stringValue = "--"
                label.textColor = NSColor(white: 0.5, alpha: 1)
                indexChangeLabels[i].stringValue = "-- --%"
                indexChangeLabels[i].textColor = NSColor(white: 0.5, alpha: 1)
                continue
            }
            let info = indices[i]
            label.stringValue = info.currentPrice.isEmpty || info.currentPrice == "--" ? "--" : info.currentPrice
            let color: NSColor
            if info.isUp { color = upColor }
            else if info.isDown { color = dnColor }
            else { color = flatColor }
            label.textColor = color
            let changeText = "\(info.changeAmount) \(info.changeRate)"
            indexChangeLabels[i].stringValue = changeText.isEmpty ? "-- --%" : changeText
            indexChangeLabels[i].textColor = color
        }
    }

    @objc private func toggleRateSort() {
        // 0 → 1(降序) → -1(升序) → 0(原序)
        switch rateSortState {
        case 0:  rateSortState =  1
        case 1:  rateSortState = -1
        default: rateSortState =  0
        }
        headerView?.rateSortState = rateSortState
        refreshDisplay()
    }

    private func rateValue(_ stock: StockInfo) -> Double {
        let s = stock.changeRate
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "+", with: "")
        return Double(s) ?? 0
    }

    private func refreshDisplay() {
        var sorted: [StockInfo]
        switch rateSortState {
        case 1:   sorted = allStocks.sorted { rateValue($0) > rateValue($1) }
        case -1:  sorted = allStocks.sorted { rateValue($0) < rateValue($1) }
        default:  sorted = allStocks
        }
        // 置顶股票始终排在第一行
        if let pinCode = StockStorage.shared.pinnedStockCode,
           let idx = sorted.firstIndex(where: { $0.code == pinCode }) {
            let pinned = sorted.remove(at: idx)
            sorted.insert(pinned, at: 0)
        }
        displayStocks = sorted
        tableView.reloadData()

        // 设置 documentView 高度，多行时才能正常滚动
        let headerHeight = tableView.headerView?.frame.height ?? 28
        let contentHeight = headerHeight + CGFloat(displayStocks.count) * tableView.rowHeight
        var frame = tableView.frame
        frame.size.height = max(contentHeight, scrollView.bounds.height)
        if frame.width <= 0 { frame.size.width = scrollView.bounds.width }
        tableView.frame = frame

        if let lastUpdate = displayStocks.first?.lastUpdate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            timeLabel.stringValue = "更新: " + formatter.string(from: lastUpdate)
        } else if !displayStocks.isEmpty {
            timeLabel.stringValue = "点击 + 添加股票"
        } else {
            timeLabel.stringValue = "暂无股票数据"
        }
    }

    // MARK: - NSMenuDelegate（右键菜单）
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard row >= 0, row < displayStocks.count else { return }
        let stock = displayStocks[row]
        let pinned = StockStorage.shared.pinnedStockCode

        if stock.code == pinned {
            let item = NSMenuItem(title: "取消置顶", action: #selector(unpinStock), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "⬆ 置顶此股票（状态栏显示）",
                                  action: #selector(pinStock(_:)), keyEquivalent: "")
            item.representedObject = stock.code
            item.target = self
            menu.addItem(item)
        }
    }

    @objc private func pinStock(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        StockStorage.shared.pinnedStockCode = code
        refreshDisplay()
        appDelegate?.updateUI()
    }

    @objc private func unpinStock() {
        StockStorage.shared.pinnedStockCode = nil
        refreshDisplay()
        appDelegate?.updateUI()
    }

    // MARK: - NSTableViewDataSource
    func numberOfRows(in tableView: NSTableView) -> Int {
        return displayStocks.count
    }
    
    // MARK: - NSTableViewDelegate
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayStocks.count else { return nil }
        let stock = displayStocks[row]
        // 复用或新建 StockRowView（layout() 会自适应 tableView 给的实际宽度）
        let identifier = NSUserInterfaceItemIdentifier("StockRow")
        let cell: StockRowView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? StockRowView {
            cell = reused
        } else {
            cell = StockRowView(frame: .zero)
            cell.identifier = identifier
        }
        let isPinned = (stock.code == StockStorage.shared.pinnedStockCode)
        cell.configure(with: stock, isPinned: isPinned)
        return cell
    }

    /// 下跌行用极淡粉红背景，与截图风格一致
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard row < displayStocks.count else { return nil }
        let stock = displayStocks[row]
        let rowView = NSTableRowView()
        rowView.wantsLayer = true
        let rateRaw = stock.changeRate
        if !rateRaw.isEmpty && rateRaw != "--" && stock.isDown {
            rowView.layer?.backgroundColor = NSColor(red: 1.0, green: 0.96, blue: 0.96, alpha: 1).cgColor
        } else {
            rowView.layer?.backgroundColor = NSColor.white.cgColor
        }
        return rowView
    }
}

// MARK: - ============ 主内容容器视图 (Tab切换) ============
class MainContentView: NSView {
    private var goldContentView: GoldContentView!
    private var stockContentView: StockContentView!
    private var tabSegment: NSSegmentedControl!
    private var currentMode: String = "gold"

    weak var appDelegate: AppDelegate? {
        didSet {
            if let delegate = appDelegate {
                stockContentView.setAppDelegate(delegate)
            }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 14
        // 浅色背景，接近白色
        layer?.backgroundColor = NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.82).cgColor

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        container.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)

        // Tab segment - 居中，regular 大小
        tabSegment = NSSegmentedControl(labels: ["  黄金  ", "  A股  "], trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
        tabSegment.selectedSegment = 0
        tabSegment.controlSize = .regular
        tabSegment.translatesAutoresizingMaskIntoConstraints = false

        // 用一个居中容器包裹 tab，右侧放关闭按钮
        let tabWrapper = NSView()
        tabWrapper.translatesAutoresizingMaskIntoConstraints = false

        // 关闭按钮（右上角）
        let closeBtn = NSButton()
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                  accessibilityDescription: "关闭")
        closeBtn.contentTintColor = NSColor(white: 0.55, alpha: 1)
        closeBtn.target = self
        closeBtn.action = #selector(closeWindow)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        tabWrapper.addSubview(tabSegment)
        tabWrapper.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            tabSegment.centerXAnchor.constraint(equalTo: tabWrapper.centerXAnchor),
            tabSegment.topAnchor.constraint(equalTo: tabWrapper.topAnchor),
            tabSegment.bottomAnchor.constraint(equalTo: tabWrapper.bottomAnchor, constant: -8),

            closeBtn.trailingAnchor.constraint(equalTo: tabWrapper.trailingAnchor, constant: -10),
            closeBtn.centerYAnchor.constraint(equalTo: tabSegment.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 18),
            closeBtn.heightAnchor.constraint(equalToConstant: 18),
        ])
        container.addArrangedSubview(tabWrapper)

        // Content views
        goldContentView = GoldContentView(frame: NSRect(x: 0, y: 0, width: 380, height: 440))
        stockContentView = StockContentView(frame: NSRect(x: 0, y: 0, width: 380, height: 440))

        container.addArrangedSubview(goldContentView)
        container.addArrangedSubview(stockContentView)

        // 强制子视图宽度填满 container
        tabWrapper.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        goldContentView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        stockContentView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        // Load saved mode
        currentMode = FundStorage.shared.displayMode
        if currentMode != "gold" && currentMode != "stock" {
            currentMode = "gold"
        }

        // 初始化时隐藏所有视图，然后根据模式显示
        goldContentView.isHidden = true
        stockContentView.isHidden = true
        updateDisplay()

        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // 右下角拖拽缩放手柄（覆盖在最上层）
        let resizeHandle = ResizeHandleView(frame: .zero)
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resizeHandle)
        NSLayoutConstraint.activate([
            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 22),
            resizeHandle.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @objc private func closeWindow() {
        window?.orderOut(nil)
        // 通知 AppDelegate 更新菜单状态
        appDelegate?.updateFloatingWindowMenuState()
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            currentMode = "gold"
        case 1:
            currentMode = "stock"
        default:
            currentMode = "gold"
        }
        FundStorage.shared.displayMode = currentMode
        updateDisplay()
        // 仅刷新菜单等 UI，状态栏仍按 statusBarDisplayMode 显示，不联动
        appDelegate?.updateUI()
    }

    private func updateDisplay() {
        let segment: Int
        switch currentMode {
        case "gold":
            segment = 0
        case "stock":
            segment = 1
        default:
            segment = 0
        }
        tabSegment.selectedSegment = segment
        goldContentView.isHidden = currentMode != "gold"
        stockContentView.isHidden = currentMode != "stock"
    }

    func updateGoldPrices(_ prices: GoldPrices) {
        goldContentView.updatePrices(prices)
    }

    func updateStocks(_ stocks: [StockInfo]) {
        stockContentView.updateStocks(stocks)
    }

    func updateIndices(_ indices: [StockInfo]) {
        stockContentView.updateIndices(indices)
    }

    func getCurrentMode() -> String {
        return currentMode
    }

    func setMode(_ mode: String) {
        guard mode == "gold" || mode == "stock" else { return }
        currentMode = mode
        FundStorage.shared.displayMode = mode
        updateDisplay()
    }
}

// MARK: - ============ App Delegate ============
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var prices = GoldPrices()
    private var funds: [FundInfo] = []
    private var stocks: [StockInfo] = []
    private var mainIndices: [StockInfo] = []  // 上证、深证、创业板
    private var refreshTimer: Timer?
    private var refreshInterval: TimeInterval = 5.0

    // 状态栏显示选项
    private var statusBarPriceKey: String = "minsheng"
    private let priceOptions: [(key: String, name: String)] = [
        ("minsheng", "民生银行"),
        ("icbc",     "工商银行"),
        ("zheshang", "浙商银行"),
        ("london",   "伦敦金"),
        ("newyork",  "纽约金")
    ]

    // Floating window
    private var floatingWindow: FloatingWindow?
    private var mainContentView: MainContentView?
    private var showFloatingWindowItem: NSMenuItem!

    // Menu items
    private var minshengItem: NSMenuItem!
    private var icbcItem: NSMenuItem!
    private var zheshangItem: NSMenuItem!

    private var londonItem: NSMenuItem!
    private var newyorkItem: NSMenuItem!
    private var lastUpdateItem: NSMenuItem!
    private var displayModeItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let saved = UserDefaults.standard.string(forKey: "statusBarPriceKey") {
            statusBarPriceKey = saved
        }

        setupStatusItem()
        setupMenu()
        setupFloatingWindow()
        startRefreshing()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "金: --"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "金价 & 股票监控", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        // Floating window toggle
        showFloatingWindowItem = NSMenuItem(title: "显示悬浮窗", action: #selector(toggleFloatingWindow), keyEquivalent: "")
        showFloatingWindowItem.target = self
        menu.addItem(showFloatingWindowItem)
        menu.addItem(NSMenuItem.separator())

        // Display mode
        displayModeItem = NSMenuItem(title: "显示模式", action: nil, keyEquivalent: "")
        let displaySubmenu = NSMenu()
        let goldItem = NSMenuItem(title: "黄金价格", action: #selector(changeDisplayMode(_:)), keyEquivalent: "")
        goldItem.representedObject = "gold"
        goldItem.target = self
        let stockItem = NSMenuItem(title: "A股行情", action: #selector(changeDisplayMode(_:)), keyEquivalent: "")
        stockItem.representedObject = "stock"
        stockItem.target = self
        displaySubmenu.addItem(goldItem)
        displaySubmenu.addItem(stockItem)
        displayModeItem.submenu = displaySubmenu
        menu.addItem(displayModeItem)
        menu.addItem(NSMenuItem.separator())

        // 国内金价
        let domesticHeader = NSMenuItem(title: "── 国内金价 ──", action: nil, keyEquivalent: "")
        domesticHeader.isEnabled = false
        menu.addItem(domesticHeader)

        minshengItem = NSMenuItem(title: "民生银行: --", action: nil, keyEquivalent: "")
        minshengItem.isEnabled = false
        menu.addItem(minshengItem)

        icbcItem = NSMenuItem(title: "工商银行: --", action: nil, keyEquivalent: "")
        icbcItem.isEnabled = false
        menu.addItem(icbcItem)

        zheshangItem = NSMenuItem(title: "浙商银行: --", action: nil, keyEquivalent: "")
        zheshangItem.isEnabled = false
        menu.addItem(zheshangItem)


        menu.addItem(NSMenuItem.separator())

        // 国际金价
        let intlHeader = NSMenuItem(title: "── 国际金价 ──", action: nil, keyEquivalent: "")
        intlHeader.isEnabled = false
        menu.addItem(intlHeader)

        londonItem = NSMenuItem(title: "伦敦金: --", action: nil, keyEquivalent: "")
        londonItem.isEnabled = false
        menu.addItem(londonItem)

        newyorkItem = NSMenuItem(title: "纽约金: --", action: nil, keyEquivalent: "")
        newyorkItem.isEnabled = false
        menu.addItem(newyorkItem)

        menu.addItem(NSMenuItem.separator())

        lastUpdateItem = NSMenuItem(title: "更新时间: --", action: nil, keyEquivalent: "")
        lastUpdateItem.isEnabled = false
        menu.addItem(lastUpdateItem)

        menu.addItem(NSMenuItem.separator())

        // 状态栏显示选项
        let statusBarItem = NSMenuItem(title: "状态栏显示", action: nil, keyEquivalent: "")
        let statusBarSubmenu = NSMenu()
        for option in priceOptions {
            let item = NSMenuItem(title: option.name, action: #selector(changeStatusBarPrice(_:)), keyEquivalent: "")
            item.representedObject = option.key
            item.target = self
            if option.key == statusBarPriceKey { item.state = .on }
            statusBarSubmenu.addItem(item)
        }
        statusBarItem.submenu = statusBarSubmenu
        menu.addItem(statusBarItem)

        // Refresh interval
        let intervalItem = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        let intervalSubmenu = NSMenu()
        for seconds in [3, 5, 10, 30, 60] {
            let item = NSMenuItem(title: "\(seconds)秒", action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.tag = seconds
            item.target = self
            if TimeInterval(seconds) == refreshInterval { item.state = .on }
            intervalSubmenu.addItem(item)
        }
        intervalItem.submenu = intervalSubmenu
        menu.addItem(intervalItem)

        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(manualRefresh), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupFloatingWindow() {
        floatingWindow = FloatingWindow()
        mainContentView = MainContentView(frame: NSRect(x: 0, y: 0, width: 380, height: 480))
        mainContentView?.appDelegate = self
        floatingWindow?.contentView = mainContentView
        floatingWindow?.setContentSize(NSSize(width: 380, height: 480))
        floatingWindow?.positionAtTopRight()
    }
    
    /// 更新悬浮窗菜单项状态（根据窗口是否可见）
    func updateFloatingWindowMenuState() {
        if floatingWindow?.isVisible == true {
            showFloatingWindowItem.title = "隐藏悬浮窗"
        } else {
            showFloatingWindowItem.title = "显示悬浮窗"
        }
    }

    private func startRefreshing() {
        Task { await refreshAll() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshAll() }
        }
    }

    @MainActor
    private func refreshAll() async {
        // 刷新金价
        prices = await GoldPriceService.shared.fetchAllPrices()

        // 刷新基金
        let savedFunds = FundStorage.shared.savedFunds
        if !savedFunds.isEmpty {
            let codes = savedFunds.map { $0.code }
            funds = await FundService.shared.fetchAllFunds(codes: codes)
        }
        
        // 刷新股票（按保存顺序排列，避免 API 返回顺序每次不同导致列表乱跳）
        let savedStocks = StockStorage.shared.savedStocks
        if !savedStocks.isEmpty {
            let codes = savedStocks.map { $0.code }
            let fetched = await StockService.shared.fetchAllStocks(codes: codes)
            let byCode = Dictionary(uniqueKeysWithValues: fetched.map { ($0.code, $0) })
            let savedByCode = Dictionary(uniqueKeysWithValues: savedStocks.map { ($0.code, $0) })
            // 网络偶发缺失或超时时，保留本地已保存的股票，避免列表短暂消失
            stocks = codes.compactMap { byCode[$0] ?? savedByCode[$0] }
        }

        // 刷新三大指数（上证、深证、创业板）
        mainIndices = await StockService.shared.fetchMainIndices()

        updateUI()
    }

    // 单独刷新基金数据（用于添加基金后立即刷新）
    @MainActor
    func refreshFunds() async {
        let savedFunds = FundStorage.shared.savedFunds
        if !savedFunds.isEmpty {
            let codes = savedFunds.map { $0.code }
            funds = await FundService.shared.fetchAllFunds(codes: codes)
            updateUI()
        }
    }
    
    // 单独刷新股票数据（用于添加股票后立即刷新）
    @MainActor
    func refreshStocks() async {
        let savedStocks = StockStorage.shared.savedStocks
        if !savedStocks.isEmpty {
            let codes = savedStocks.map { $0.code }
            let fetched = await StockService.shared.fetchAllStocks(codes: codes)
            let byCode = Dictionary(uniqueKeysWithValues: fetched.map { ($0.code, $0) })
            let savedByCode = Dictionary(uniqueKeysWithValues: savedStocks.map { ($0.code, $0) })
            // 网络偶发缺失或超时时，保留本地已保存的股票，避免列表短暂消失
            stocks = codes.compactMap { byCode[$0] ?? savedByCode[$0] }
            updateUI()
        }
    }

    @MainActor
    func updateUI() {
        // Status bar（仅由「显示模式」菜单控制，与悬浮窗页签无关）
        if let button = statusItem.button {
            let mode = FundStorage.shared.statusBarDisplayMode
            if mode == "gold" {
                let info = prices.priceInfo(for: statusBarPriceKey)
                button.title = "金: \(info.price)"
            } else if mode == "fund" {
                // 显示基金概览
                if let firstFund = funds.first {
                    let arrow = firstFund.isUp ? "📈" : "📉"
                    button.title = "\(firstFund.code): \(firstFund.estimatedValue) \(arrow)\(firstFund.estimatedRate)%"
                } else {
                    button.title = "基金: --"
                }
            } else if mode == "stock" {
                if stocks.isEmpty {
                    button.title = "A股: --"
                } else {
                    // 优先显示置顶股票，否则显示第一个
                    let pinCode   = StockStorage.shared.pinnedStockCode
                    let showStock = stocks.first(where: { $0.code == pinCode }) ?? stocks.first!
                    let name      = showStock.name.isEmpty ? showStock.code : showStock.name
                    let price     = showStock.currentPrice.isEmpty || showStock.currentPrice == "--"
                                    ? "--" : showStock.currentPrice
                    if showStock.changeRate.isEmpty || showStock.changeRate == "--" {
                        button.title = "\(name) \(price)"
                    } else {
                        let arrow = showStock.isUp ? "▲" : (showStock.isDown ? "▼" : "—")
                        var rate  = showStock.changeRate
                        if !rate.hasPrefix("+") && !rate.hasPrefix("-") {
                            rate = showStock.isUp ? "+" + rate : (showStock.isDown ? rate : rate)
                        }
                        if !rate.hasSuffix("%") { rate += "%" }
                        button.title = "\(name) \(price) \(arrow)\(rate)"
                    }
                }
            }
        }

        // Menu items
        minshengItem.title = formatMenuItem(name: "民生银行", info: prices.minsheng, unit: "元/克")
        icbcItem.title     = formatMenuItem(name: "工商银行", info: prices.icbc,     unit: "元/克")
        zheshangItem.title = formatMenuItem(name: "浙商银行", info: prices.zheshang, unit: "元/克")

        londonItem.title   = formatMenuItem(name: "伦敦金",   info: prices.london,   unit: "$/oz")
        newyorkItem.title  = formatMenuItem(name: "纽约金",   info: prices.newyork,  unit: "$/oz")

        if let lastUpdate = prices.lastUpdate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            lastUpdateItem.title = "更新时间: \(formatter.string(from: lastUpdate))"
        }

        // Update content views
        mainContentView?.updateGoldPrices(prices)
        mainContentView?.updateStocks(stocks)
        mainContentView?.updateIndices(mainIndices)

        // 显示模式菜单勾选（表示当前状态栏显示的是黄金还是 A 股）
        if let submenu = displayModeItem.submenu {
            for item in submenu.items {
                let mode = item.representedObject as? String ?? ""
                item.state = mode == FundStorage.shared.statusBarDisplayMode ? .on : .off
            }
        }
    }

    private func formatMenuItem(name: String, info: PriceInfo, unit: String) -> String {
        var text = "\(name): \(info.price) \(unit)"
        if !info.changeRate.isEmpty {
            let arrow = info.isUp ? "📈" : "📉"
            text += " \(arrow)\(info.changeRate)"
        }
        return text
    }

    @objc private func toggleFloatingWindow() {
        if floatingWindow?.isVisible == true {
            floatingWindow?.orderOut(nil)
        } else {
            floatingWindow?.orderFront(nil)
        }
        updateFloatingWindowMenuState()
    }

    @MainActor @objc private func changeDisplayMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }

        if let submenu = sender.menu {
            for item in submenu.items { item.state = .off }
        }
        sender.state = .on

        // 仅更新状态栏显示模式，不联动悬浮窗页签
        FundStorage.shared.statusBarDisplayMode = mode
        updateUI()
    }

    @MainActor @objc private func changeStatusBarPrice(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }

        if let submenu = sender.menu {
            for item in submenu.items { item.state = .off }
        }
        sender.state = .on

        statusBarPriceKey = key
        UserDefaults.standard.set(key, forKey: "statusBarPriceKey")

        updateUI()
    }

    @objc private func changeInterval(_ sender: NSMenuItem) {
        if let submenu = sender.menu {
            for item in submenu.items { item.state = .off }
        }
        sender.state = .on
        refreshInterval = TimeInterval(sender.tag)
        startRefreshing()
    }

    @objc private func manualRefresh() {
        Task { await refreshAll() }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()