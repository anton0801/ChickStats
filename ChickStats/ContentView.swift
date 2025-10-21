import SwiftUI
import WebKit
import UserNotifications
import Network
import Firebase
import FirebaseMessaging
import AppsFlyerLib
import AppTrackingTransparency

extension Color {
    static let background = Color(hex: "#1E1E2C")
    static let accentYellow = Color(hex: "#FFD93D")
    static let accentOrange = Color(hex: "#FF8C42")
    static let graphTurquoise = Color(hex: "#4ACFAC")
    static let graphRed = Color(hex: "#FF5C5C")
    static let graphGreen = Color(hex: "#6CFF72")
    static let secondaryBackground = Color(hex: "#2A2A3A")
    static let textPrimary = Color.white
    static let textSecondary = Color.gray
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// Assume custom fonts like Nunito are added to the project
extension Font {
    static let title = Font.custom("Nunito-Bold", size: 24)
    static let headline = Font.custom("Nunito-SemiBold", size: 18)
    static let bodyText = Font.custom("Nunito-Regular", size: 16)
    static let caption = Font.custom("Nunito-Regular", size: 14)
}

// Data Models
class FarmData: ObservableObject {
    @Published var dailyEggs: [Date: Int] = [:] // Date to egg count
    @Published var eggWeights: [Date: [Double]] = [:] // Date to array of weights
    @Published var expenses: [Expense] = []
    @Published var weatherData: [Date: Weather] = [:]
    @Published var flockSize: Int = 50 // Default flock size
    @Published var currency: String = "$"
    @Published var weightUnit: String = "g"
    @Published var weatherAPIKey: String = "" // For real API
    @Published var location: String = "London" // For weather
    
    struct Expense: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Double
        let category: Category
        
        enum Category: String, CaseIterable, Identifiable {
            case feed = "Feed"
            case electricity = "Electricity"
            case bedding = "Bedding"
            case veterinary = "Veterinary"
            case other = "Other"
            
            var id: String { rawValue }
        }
    }
    
    struct Weather {
        let temperature: Double
        let condition: String // e.g., "Sunny"
    }
    
    // Helper functions
    func addEggs(date: Date = Date(), count: Int) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        dailyEggs[startOfDay] = (dailyEggs[startOfDay] ?? 0) + count
    }
    
    func addEggWeight(date: Date = Date(), weight: Double) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        if var weights = eggWeights[startOfDay] {
            weights.append(weight)
            eggWeights[startOfDay] = weights
        } else {
            eggWeights[startOfDay] = [weight]
        }
    }
    
    func addExpense(amount: Double, category: Expense.Category) {
        expenses.append(Expense(date: Date(), amount: amount, category: category))
    }
    
    func addWeather(date: Date = Date(), temp: Double, condition: String) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        weatherData[startOfDay] = Weather(temperature: temp, condition: condition)
    }
    
    // Fetch real weather (placeholder)
    func fetchWeather() async {
        guard !weatherAPIKey.isEmpty else { return }
        // Use OpenWeatherMap API
        let urlString = "https://api.openweathermap.org/data/2.5/weather?q=\(location)&appid=\(weatherAPIKey)&units=metric"
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONDecoder().decode(WeatherResponse.self, from: data)
            addWeather(temp: json.main.temp, condition: json.weather.first?.description ?? "Unknown")
        } catch {
            print("Weather fetch error: \(error)")
        }
    }
    
    struct WeatherResponse: Decodable {
        let main: Main
        let weather: [WeatherItem]
        
        struct Main: Decodable {
            let temp: Double
        }
        
        struct WeatherItem: Decodable {
            let description: String
        }
    }
    
    // Calculations
    func eggsToday() -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        return dailyEggs[today] ?? 0
    }
    
    func averageEggWeightToday() -> Double {
        let today = Calendar.current.startOfDay(for: Date())
        guard let weights = eggWeights[today], !weights.isEmpty else { return 0 }
        return weights.reduce(0, +) / Double(weights.count)
    }
    
    func expensesThisWeek() -> Double {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return expenses.filter { $0.date >= weekAgo }.reduce(0) { $0 + $1.amount }
    }
    
    func currentWeather() -> Weather? {
        let today = Calendar.current.startOfDay(for: Date())
        return weatherData[today]
    }
    
    func eggsLast7Days() -> [Int] {
        var data: [Int] = []
        let calendar = Calendar.current
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let startOfDay = calendar.startOfDay(for: date)
                data.append(dailyEggs[startOfDay] ?? 0)
            } else {
                data.append(0)
            }
        }
        return data.reversed()
    }
    
    func averageEggs(period: Period) -> Double {
        let data = eggsData(for: period)
        guard !data.isEmpty else { return 0 }
        return Double(data.reduce(0, +)) / Double(data.count)
    }
    
    private func eggsData(for period: Period) -> [Int] {
        var data: [Int] = []
        let calendar = Calendar.current
        let days: Int
        switch period {
        case .week: days = 7
        case .month: days = 30
        }
        for i in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let startOfDay = calendar.startOfDay(for: date)
                data.append(dailyEggs[startOfDay] ?? 0)
            } else {
                data.append(0)
            }
        }
        return data
    }
    
    enum Period {
        case week, month
    }
    
    func comparisonWithPrevious(period: Period) -> Double {
        let currentData = eggsData(for: period)
        let days = currentData.count
        let calendar = Calendar.current
        let previousStart = calendar.date(byAdding: .day, value: -days * 2, to: Date())!
        let previousEnd = calendar.date(byAdding: .day, value: -days, to: Date())!
        let previousData = dailyEggs.filter { $0.key >= previousStart && $0.key < previousEnd }.map { $0.value }
        let currentAvg = currentData.isEmpty ? 0 : Double(currentData.reduce(0, +)) / Double(currentData.count)
        let previousAvg = previousData.isEmpty ? 0 : Double(previousData.reduce(0, +)) / Double(previousData.count)
        return currentAvg - previousAvg
    }
    
    func weightClassification(weight: Double) -> String {
        if weight < 53 { return "S" }
        else if weight < 63 { return "M" }
        else if weight < 73 { return "L" }
        else { return "XL" }
    }
    
    func weightDistribution() -> [String: Int] {
        var dist: [String: Int] = ["S": 0, "M": 0, "L": 0, "XL": 0]
        for weights in eggWeights.values {
            for w in weights {
                let cat = weightClassification(weight: w)
                dist[cat] = (dist[cat] ?? 0) + 1
            }
        }
        return dist
    }
    
    func averageWeightByWeek() -> [Double] {
        var averages: [Double] = []
        let calendar = Calendar.current
        for week in 0..<4 {
            let start = calendar.date(byAdding: .day, value: -(week + 1) * 7, to: Date())!
            let end = calendar.date(byAdding: .day, value: -week * 7, to: Date())!
            let weekWeights = eggWeights.filter { $0.key >= start && $0.key < end }.flatMap { $0.value }
            let avg = weekWeights.isEmpty ? 0 : weekWeights.reduce(0, +) / Double(weekWeights.count)
            averages.append(avg)
        }
        return averages.reversed()
    }
    
    func expenseByCategory() -> [Expense.Category: Double] {
        var dict: [Expense.Category: Double] = [:]
        for exp in expenses {
            dict[exp.category] = (dict[exp.category] ?? 0) + exp.amount
        }
        return dict
    }
    
    func costPerEgg() -> Double {
        let totalExpenses = expenses.reduce(0) { $0 + $1.amount }
        let totalEggs = dailyEggs.reduce(0) { $0 + $1.value }
        return totalEggs > 0 ? totalExpenses / Double(totalEggs) : 0
    }
    
    // Mock forecast
    func forecastEggs(days: Int) -> [Int] {
        let avg = averageEggs(period: .week)
        var forecast: [Int] = []
        for _ in 0..<days {
            let mockTemp = Double.random(in: 15...25)
            var adjustment = 1.0
            if mockTemp > 30 { adjustment = 0.9 }
            else if mockTemp < 10 { adjustment = 0.8 }
            forecast.append(Int(avg * adjustment))
        }
        return forecast
    }
    
    func profitability(salePrice: Double = 0.2) -> Double {
        return salePrice - costPerEgg()
    }
}

// Enhanced Custom Charts with labels and grids
struct LineChart: View {
    let data: [Double]
    let color: Color
    let minY: Double?
    let maxY: Double?
    
    init(data: [Double], color: Color, minY: Double? = nil, maxY: Double? = nil) {
        self.data = data
        self.color = color
        self.minY = minY ?? data.min()
        self.maxY = maxY ?? data.max()
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Grid
                Path { path in
                    for i in 0...4 {
                        let y = geo.size.height * (1 - CGFloat(Float(i)/4.0))
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.textSecondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                
                // Line
                Path { path in
                    guard !data.isEmpty, let minY = minY, let maxY = maxY else { return }
                    let rangeY = maxY - minY > 0 ? maxY - minY : 1
                    let stepX = geo.size.width / CGFloat(data.count - 1)
                    path.move(to: CGPoint(x: 0, y: geo.size.height * (1 - CGFloat((data[0] - minY) / rangeY))))
                    for i in 1..<data.count {
                        let y = geo.size.height * (1 - CGFloat((data[i] - minY) / rangeY))
                        path.addLine(to: CGPoint(x: CGFloat(i) * stepX, y: y))
                    }
                }
                .stroke(color, lineWidth: 3)
                .shadow(color: color.opacity(0.5), radius: 2, x: 0, y: 2)
            }
        }
    }
}

struct BarChart: View {
    let data: [Double]
    let colors: [Color]
    
    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(data.indices, id: \.self) { i in
                    Rectangle()
                        .fill(LinearGradient(gradient: Gradient(colors: [colors[i % colors.count].opacity(0.8), colors[i % colors.count]]), startPoint: .top, endPoint: .bottom))
                        .frame(height: geo.size.height * CGFloat(data[i] / (data.max() ?? 1)))
                        .cornerRadius(4)
                        .shadow(radius: 2)
                }
            }
        }
    }
}

struct PieChart: View {
    let slices: [Double]
    let colors: [Color]
    
    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2
            var startAngle: Angle = .zero
            ZStack {
                ForEach(0..<slices.count, id: \.self) { i in
                    let endAngle = startAngle + .radians(2 * .pi * slices[i])
                    Path { path in
                        path.move(to: CGPoint(x: radius, y: radius))
                        path.addArc(center: CGPoint(x: radius, y: radius), radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                    }
                    .fill(colors[i % colors.count])
                    .shadow(radius: 2)
                    .onAppear {
                        startAngle = endAngle
                    }
                }
            }
        }
    }
}


struct ContentView: View {
    @StateObject private var farmData = FarmData()
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                        .environment(\.symbolVariants, .none)
                }
            EggsView()
                .tabItem {
                    Label("Eggs", systemImage: "oval.portrait")
                }
            WeightView()
                .tabItem {
                    Label("Weight", systemImage: "scalemass.fill")
                }
            ExpensesView()
                .tabItem {
                    Label("Expenses", systemImage: "dollarsign.circle.fill")
                }
            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }
        }
        .environmentObject(farmData)
        .onAppear {
            Task {
                await farmData.fetchWeather()
            }
        }
    }
}

// Home View
struct HomeView: View {
    @EnvironmentObject var farmData: FarmData
    @State private var showAddData = false
    @State private var showSettings = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    CardView(title: "Eggs Today", value: "\(farmData.eggsToday())", icon: "oval.portrait", color: .graphGreen)
                    CardView(title: "Avg Weight", value: String(format: "%.1f %@", farmData.averageEggWeightToday(), farmData.weightUnit), icon: "scalemass.fill", color: .graphTurquoise)
                    CardView(title: "Expenses Week", value: "\(farmData.currency) \(String(format: "%.2f", farmData.expensesThisWeek()))", icon: "dollarsign.circle.fill", color: .graphRed)
                    if let weather = farmData.currentWeather() {
                        CardView(title: "Weather", value: "\(Int(weather.temperature))°C, \(weather.condition)", icon: "cloud.sun.fill", color: .accentYellow)
                    }
                }
                .padding()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Egg Production Last 7 Days")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    LineChart(data: farmData.eggsLast7Days().map { Double($0) }, color: .graphGreen)
                        .frame(height: 200)
                        .background(Color.secondaryBackground)
                        .cornerRadius(16)
                        .shadow(radius: 5)
                }
                .padding()
                
                Button("Add Data") {
                    showAddData = true
                }
                .buttonStyle(GradientButtonStyle())
                .padding(.horizontal)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image("gearshape.fill")
                            .foregroundColor(.accentYellow)
                    }
                }
            }
            .sheet(isPresented: $showAddData) {
                AddDataView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(LinearGradient(gradient: Gradient(colors: [.accentYellow, .accentOrange]), startPoint: .leading, endPoint: .trailing))
            .foregroundColor(.background)
            .font(.headline)
            .clipShape(Capsule())
            .shadow(color: .accentYellow.opacity(0.5), radius: 5, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct CardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text(value)
                    .font(.title)
                    .foregroundColor(.textPrimary)
                    .bold()
            }
            Spacer()
        }
        .padding()
        .background(Color.secondaryBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
    }
}

// Add Data View
struct AddDataView: View {
    @EnvironmentObject var farmData: FarmData
    @Environment(\.presentationMode) var presentationMode
    @State private var eggCount: String = ""
    @State private var eggWeight: String = ""
    @State private var expenseAmount: String = ""
    @State private var expenseCategory: FarmData.Expense.Category = .feed
    @State private var temp: String = ""
    @State private var condition: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Eggs").font(.headline)) {
                    TextField("Egg Count Today", text: $eggCount)
                        .keyboardType(.numberPad)
                }
                Section(header: Text("Egg Weight").font(.headline)) {
                    TextField("Weight (\(farmData.weightUnit))", text: $eggWeight)
                        .keyboardType(.decimalPad)
                }
                Section(header: Text("Expenses").font(.headline)) {
                    TextField("Amount", text: $expenseAmount)
                        .keyboardType(.decimalPad)
                    Picker("Category", selection: $expenseCategory) {
                        ForEach(FarmData.Expense.Category.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                }
                Section(header: Text("Weather (Manual)").font(.headline)) {
                    TextField("Temperature (°C)", text: $temp)
                        .keyboardType(.decimalPad)
                    TextField("Condition (e.g., Sunny)", text: $condition)
                }
            }
            .navigationTitle("Add Data")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveData()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .background(Color.background)
        }
    }
    
    private func saveData() {
        if let count = Int(eggCount), count > 0 { farmData.addEggs(count: count) }
        if let weight = Double(eggWeight), weight > 0 { farmData.addEggWeight(weight: weight) }
        if let amount = Double(expenseAmount), amount > 0 { farmData.addExpense(amount: amount, category: expenseCategory) }
        if let t = Double(temp) { farmData.addWeather(temp: t, condition: condition) }
    }
}

// Eggs View
struct EggsView: View {
    @EnvironmentObject var farmData: FarmData
    @State private var eggCount: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        TextField("Enter Egg Count", text: $eggCount)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Add") {
                            if let count = Int(eggCount), count > 0 {
                                farmData.addEggs(count: count)
                                eggCount = ""
                            }
                        }
                        .buttonStyle(GradientButtonStyle())
                    }
                    .padding()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily Eggs")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        LineChart(data: farmData.eggsLast7Days().map { Double($0) }, color: .graphTurquoise)
                            .frame(height: 250)
                            .background(Color.secondaryBackground)
                            .cornerRadius(16)
                            .shadow(radius: 5)
                    }
                    .padding(.horizontal)
                    
                    StatisticRow(label: "Avg Week", value: String(format: "%.1f", farmData.averageEggs(period: .week)))
                    StatisticRow(label: "Avg Month", value: String(format: "%.1f", farmData.averageEggs(period: .month)))
                    
                    let comp = farmData.comparisonWithPrevious(period: .week)
                    StatisticRow(label: "vs Last Week", value: String(format: "%.1f", comp), color: comp > 0 ? .graphGreen : .graphRed)
                }
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Eggs")
        }
        .navigationViewStyle(.stack)
    }
}

struct StatisticRow: View {
    let label: String
    let value: String
    let color: Color
    
    init(label: String, value: String, color: Color = Color.textPrimary) {
        self.label = label
        self.value = value
        self.color = color
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.bodyText)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.bodyText)
                .foregroundColor(color)
                .bold()
        }
        .padding(.horizontal)
    }
}

// Weight View
struct WeightView: View {
    @EnvironmentObject var farmData: FarmData
    @State private var weight: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        TextField("Enter Weight (\(farmData.weightUnit))", text: $weight)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Add") {
                            if let w = Double(weight), w > 0 {
                                farmData.addEggWeight(weight: w)
                                weight = ""
                            }
                        }
                        .buttonStyle(GradientButtonStyle())
                    }
                    .padding()
                    
                    let dist = farmData.weightDistribution()
                    let distData = [Double(dist["S"] ?? 0), Double(dist["M"] ?? 0), Double(dist["L"] ?? 0), Double(dist["XL"] ?? 0)]
                    let barColors: [Color] = [.graphRed, .graphTurquoise, .graphGreen, .accentOrange]
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weight Distribution")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        BarChart(data: distData, colors: barColors)
                            .frame(height: 250)
                            .background(Color.secondaryBackground)
                            .cornerRadius(16)
                            .shadow(radius: 5)
                        HStack(spacing: 20) {
                            ForEach(["S", "M", "L", "XL"], id: \.self) { cat in
                                Text(cat)
                                    .foregroundColor(.textSecondary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Avg Weight by Week")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        LineChart(data: farmData.averageWeightByWeek(), color: .graphTurquoise)
                            .frame(height: 200)
                            .background(Color.secondaryBackground)
                            .cornerRadius(16)
                            .shadow(radius: 5)
                    }
                    .padding(.horizontal)
                }
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Weight")
        }
        .navigationViewStyle(.stack)
    }
}

// Expenses View
struct ExpensesView: View {
    @EnvironmentObject var farmData: FarmData
    @State private var amount: String = ""
    @State private var category: FarmData.Expense.Category = .feed
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        TextField("Amount", text: $amount)
                            .textFieldStyle(.roundedBorder)
                        Picker("Category", selection: $category) {
                            ForEach(FarmData.Expense.Category.allCases) { cat in
                                Text(cat.rawValue).tag(cat)
                            }
                        }
                        .pickerStyle(.menu)
                        Button("Add") {
                            if let a = Double(amount), a > 0 {
                                farmData.addExpense(amount: a, category: category)
                                amount = ""
                            }
                        }
                        .buttonStyle(GradientButtonStyle())
                    }
                    .padding()
                    
                    List {
                        ForEach(farmData.expenses) { exp in
                            HStack {
                                Text(exp.category.rawValue)
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Text("\(farmData.currency) \(String(format: "%.2f", exp.amount))")
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .onDelete { indices in
                            farmData.expenses.remove(atOffsets: indices)
                        }
                    }
                    .listStyle(.plain)
                    .background(Color.secondaryBackground)
                    .cornerRadius(16)
                    .shadow(radius: 5)
                    .frame(height: 250)
                    .padding(.horizontal)
                    
                    let catData = farmData.expenseByCategory()
                    let total = catData.values.reduce(0, +) + 0.0001 // Avoid division by zero
                    let slices = FarmData.Expense.Category.allCases.map { catData[$0] ?? 0 / total }
                    let pieColors: [Color] = [.graphRed, .graphGreen, .graphTurquoise, .accentYellow, .accentOrange]
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Expense Categories")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        PieChart(slices: slices, colors: pieColors)
                            .frame(height: 250)
                            .padding()
                    }
                    .background(Color.secondaryBackground)
                    .cornerRadius(16)
                    .shadow(radius: 5)
                    .padding(.horizontal)
                    
                    StatisticRow(label: "Cost per Egg", value: "\(farmData.currency) \(String(format: "%.2f", farmData.costPerEgg()))")
                        .padding(.horizontal)
                }
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Expenses")
        }
        .navigationViewStyle(.stack)
    }
}

// Stats View
struct StatsView: View {
    @EnvironmentObject var farmData: FarmData
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Combined Metrics")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        ZStack {
                            BarChart(data: farmData.averageWeightByWeek(), colors: [.graphRed])
                                .opacity(0.5)
                                .frame(height: 300)
                            LineChart(data: farmData.eggsLast7Days().map { Double($0) }, color: .graphGreen)
                                .frame(height: 300)
                            LineChart(data: farmData.averageWeightByWeek(), color: .graphTurquoise)
                                .frame(height: 300)
                        }
                        .background(Color.secondaryBackground)
                        .cornerRadius(16)
                        .shadow(radius: 5)
                    }
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Egg Forecast (7 days)")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        LineChart(data: farmData.forecastEggs(days: 7).map { Double($0) }, color: .accentYellow)
                            .frame(height: 200)
                            .background(Color.secondaryBackground)
                            .cornerRadius(16)
                            .shadow(radius: 5)
                    }
                    .padding(.horizontal)
                    
                    let profit = farmData.profitability()
                    StatisticRow(label: "Profitability per Egg", value: "\(farmData.currency) \(String(format: "%.2f", profit))", color: profit > 0 ? .graphGreen : .graphRed)
                        .padding(.horizontal)
                    
                    Button("Export Report") {
                        // Implement export (e.g., generate CSV)
                        exportReport()
                    }
                    .buttonStyle(GradientButtonStyle())
                    .padding(.horizontal)
                }
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Statistics")
        }
        .navigationViewStyle(.stack)
    }
    
    private func exportReport() {
        // Placeholder: Generate CSV or PDF
        print("Exporting report...")
        // Use UIActivityViewController for sharing
    }
}

// Settings View
struct SettingsView: View {
    @EnvironmentObject var farmData: FarmData
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("General").font(.headline)) {
                    TextField("Currency", text: $farmData.currency)
                    TextField("Weight Unit", text: $farmData.weightUnit)
                    Stepper("Flock Size: \(farmData.flockSize)", value: $farmData.flockSize, in: 1...1000)
                }
                Section(header: Text("Weather API").font(.headline)) {
                    TextField("API Key", text: $farmData.weatherAPIKey)
                    TextField("Location", text: $farmData.location)
                }
                Section(header: Text("Notifications").font(.headline)) {
                    Text("Coming soon: Notifications for alerts")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .background(Color.background)
        }
    }
}

@main
struct ChickStatsApp: App {
    
    @UIApplicationDelegateAdaptor(ApplicationDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ChickLaunchInterface()
                .preferredColorScheme(.dark)
        }
    }
}


class ApplicationDelegate: UIResponder, UIApplicationDelegate, AppsFlyerLibDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    
    private var conversionData: [AnyHashable: Any] = [:]
    
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        processPushPayload(userInfo)
        completionHandler(.newData)
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
    
        setUpAppsfluer()
        
        if let notifPayload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            processPushPayload(notifPayload)
        }
        
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(activateTracking),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        return true
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let payload = notification.request.content.userInfo
        processPushPayload(payload)
        completionHandler([.banner, .sound])
    }
    
    private func setUpAppsfluer() {
        AppsFlyerLib.shared().appsFlyerDevKey = "3ERPRZB3HpWKFpHixe8pQc"
        AppsFlyerLib.shared().appleAppID = "6753870535"
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().start()
    }
    
    private func processPushPayload(_ payload: [AnyHashable: Any]) {
        var linkStr: String?
        if let link = payload["url"] as? String {
            linkStr = link
        } else if let info = payload["data"] as? [String: Any], let link = info["url"] as? String {
            linkStr = link
        }
        
        if let linkStr = linkStr {
            UserDefaults.standard.set(linkStr, forKey: "temp_url")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NotificationCenter.default.post(name: NSNotification.Name("LoadTempURL"), object: nil, userInfo: ["tempUrl": linkStr])
            }
        }
    }
    
    
    // AppsFlyer callbacks
    func onConversionDataSuccess(_ data: [AnyHashable: Any]) {
        conversionData = data
        NotificationCenter.default.post(name: Notification.Name("ConversionDataReceived"), object: nil, userInfo: ["conversionData": conversionData])
    }
    
    
    @objc private func activateTracking() {
        AppsFlyerLib.shared().start()
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { _ in
            }
        }
    }
    
    func onConversionDataFail(_ error: Error) {
        NotificationCenter.default.post(name: Notification.Name("ConversionDataFailed"), object: nil, userInfo: ["conversionData": [:]])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let payload = response.notification.request.content.userInfo
        processPushPayload(payload)
        completionHandler()
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, err in
            if let _ = err {
            }
            UserDefaults.standard.set(token, forKey: "fcm_token")
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }
    
}

#Preview {
    ChickLaunchInterface()
}

class ContentDisplayHandler: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let statsManager: StatsManager
    
    private var redirectCounter: Int = 0
    private let maxRedirects: Int = 70 // For testing
    private var lastWorkingPath: URL?

    func webView(_ displayView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let secureSpace = challenge.protectionSpace
        if secureSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let trustRef = secureSpace.serverTrust {
                let authCred = URLCredential(trust: trustRef)
                completionHandler(.useCredential, authCred)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    init(manager: StatsManager) {
        self.statsManager = manager
        super.init()
    }
    
    func webView(
        _ displayView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }
        
        let newDisplay = DisplayCreator.buildPrimaryDisplay(with: configuration)
        setupNewDisplay(newDisplay)
        attachNewDisplay(newDisplay)
        
        statsManager.additionalDisplays.append(newDisplay)
        if checkLoadValidity(in: newDisplay, for: navigationAction.request) {
            newDisplay.load(navigationAction.request)
        }
        return newDisplay
    }
    
    func webView(_ displayView: WKWebView, didFinish navigation: WKNavigation!) {
        // Inject rules to prevent scaling via meta and styles
        let scriptInjection = """
                let viewportMeta = document.createElement('meta');
                viewportMeta.name = 'viewport';
                viewportMeta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                document.getElementsByTagName('head')[0].appendChild(viewportMeta);
                let customStyle = document.createElement('style');
                customStyle.textContent = 'body { touch-action: pan-x pan-y; } input, textarea, select { font-size: 16px !important; maximum-scale=1.0; }';
                document.getElementsByTagName('head')[0].appendChild(customStyle);
                document.addEventListener('gesturestart', function(e) { e.preventDefault(); });
                """;
        displayView.evaluateJavaScript(scriptInjection) { _, issue in
            if let issue = issue {
                print("Script injection failed: \(issue)")
            }
        }
    }
    
    func webView(_ displayView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        redirectCounter += 1
        if redirectCounter > maxRedirects {
            displayView.stopLoading()
            if let fallbackPath = lastWorkingPath {
                displayView.load(URLRequest(url: fallbackPath))
            }
            return
        }
        lastWorkingPath = displayView.url // Save the previous good path
        saveSessionData(from: displayView)
    }
    
    func webView(_ displayView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorHTTPTooManyRedirects, let fallbackPath = lastWorkingPath {
            displayView.load(URLRequest(url: fallbackPath))
        }
    }
    
    func webView(
        _ displayView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let path = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        if path.absoluteString.hasPrefix("http") || path.absoluteString.hasPrefix("https") {
            lastWorkingPath = path
            decisionHandler(.allow)
        } else {
            UIApplication.shared.open(path, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
        }
    }
    
    private func setupNewDisplay(_ display: WKWebView) {
        display.translatesAutoresizingMaskIntoConstraints = false
        display.scrollView.isScrollEnabled = true
        display.scrollView.minimumZoomScale = 1.0
        display.scrollView.maximumZoomScale = 1.0
        display.scrollView.bouncesZoom = false
        display.allowsBackForwardNavigationGestures = true
        display.navigationDelegate = self
        display.uiDelegate = self
        statsManager.primaryDisplay.addSubview(display)
        
        // Add edge swipe for layered display
        let edgeSwipe = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgeSwipe(_:)))
        edgeSwipe.edges = .left
        display.addGestureRecognizer(edgeSwipe)
    }
    
    private func attachNewDisplay(_ display: WKWebView) {
        NSLayoutConstraint.activate([
            display.leadingAnchor.constraint(equalTo: statsManager.primaryDisplay.leadingAnchor),
            display.trailingAnchor.constraint(equalTo: statsManager.primaryDisplay.trailingAnchor),
            display.topAnchor.constraint(equalTo: statsManager.primaryDisplay.topAnchor),
            display.bottomAnchor.constraint(equalTo: statsManager.primaryDisplay.bottomAnchor)
        ])
    }
    
    private func checkLoadValidity(in display: WKWebView, for loadReq: URLRequest) -> Bool {
        if let pathStr = loadReq.url?.absoluteString, !pathStr.isEmpty, pathStr != "about:blank" {
            return true
        }
        return false
    }
    
    private func saveSessionData(from display: WKWebView) {
        display.configuration.websiteDataStore.httpCookieStore.getAllCookies { sessionItems in
            var groupedItems: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            for item in sessionItems {
                var itemsByGroup = groupedItems[item.domain] ?? [:]
                itemsByGroup[item.name] = item.properties as? [HTTPCookiePropertyKey: Any]
                groupedItems[item.domain] = itemsByGroup
            }
            UserDefaults.standard.set(groupedItems, forKey: "persisted_session")
        }
    }
}

struct DisplayCreator {
    
    static func buildPrimaryDisplay(with config: WKWebViewConfiguration? = nil) -> WKWebView {
        let settings = config ?? prepareSettings()
        return WKWebView(frame: .zero, configuration: settings)
    }
    
    private static func prepareSettings() -> WKWebViewConfiguration {
        let settings = WKWebViewConfiguration()
        settings.allowsInlineMediaPlayback = true
        settings.preferences = prepareOptions()
        settings.defaultWebpagePreferences = preparePageOptions()
        settings.requiresUserActionForMediaPlayback = false
        return settings
    }
    
    private static func prepareOptions() -> WKPreferences {
        let options = WKPreferences()
        options.javaScriptEnabled = true
        options.javaScriptCanOpenWindowsAutomatically = true
        return options
    }
    
    private static func preparePageOptions() -> WKWebpagePreferences {
        let options = WKWebpagePreferences()
        options.allowsContentJavaScript = true
        return options
    }
    
    static func shouldClearExtras(_ primary: WKWebView, _ additions: [WKWebView], currentPath: URL?) -> Bool {
        if !additions.isEmpty {
            additions.forEach { $0.removeFromSuperview() }
            if let path = currentPath {
                primary.load(URLRequest(url: path))
            }
            return true
        } else if primary.canGoBack {
            primary.goBack()
            return false
        }
        return false
    }
}

extension Notification.Name {
    static let displayEvents = Notification.Name("display_actions")
}

class StatsManager: ObservableObject {
    @Published var primaryDisplay: WKWebView!
    @Published var additionalDisplays: [WKWebView] = []
    
    func setupPrimaryDisplay() {
        primaryDisplay = DisplayCreator.buildPrimaryDisplay()
        primaryDisplay.scrollView.minimumZoomScale = 1.0
        primaryDisplay.scrollView.maximumZoomScale = 1.0
        primaryDisplay.scrollView.bouncesZoom = false
        primaryDisplay.allowsBackForwardNavigationGestures = true
    }
    
    func loadPersistedSession() {
        guard let persistedData = UserDefaults.standard.dictionary(forKey: "persisted_session") as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }
        let dataStore = primaryDisplay.configuration.websiteDataStore.httpCookieStore
        
        persistedData.values.flatMap { $0.values }.forEach { attributes in
            if let sessionItem = HTTPCookie(properties: attributes as! [HTTPCookiePropertyKey: Any]) {
                dataStore.setCookie(sessionItem)
            }
        }
    }
    
    func refreshDisplay() {
        primaryDisplay.reload()
    }
    
    func removeAdditions(currentPath: URL?) {
        if !additionalDisplays.isEmpty {
            if let latestAddition = additionalDisplays.last {
                latestAddition.removeFromSuperview()
                additionalDisplays.removeLast()
            }
            if let path = currentPath {
                primaryDisplay.load(URLRequest(url: path))
            }
        } else if primaryDisplay.canGoBack {
            primaryDisplay.goBack()
        }
    }
    
    func closeLatestAddition() {
        if let latestAddition = additionalDisplays.last {
            latestAddition.removeFromSuperview()
            additionalDisplays.removeLast()
        }
    }
}

struct MainDisplayWrapper: UIViewRepresentable {
    let destinationPath: URL
    @StateObject private var manager = StatsManager()
    
    func makeUIView(context: Context) -> WKWebView {
        manager.setupPrimaryDisplay()
        manager.primaryDisplay.uiDelegate = context.coordinator
        manager.primaryDisplay.navigationDelegate = context.coordinator
    
        manager.loadPersistedSession()
        manager.primaryDisplay.load(URLRequest(url: destinationPath))
        return manager.primaryDisplay
    }
    
    func updateUIView(_ display: WKWebView, context: Context) {
    }
    
    func makeCoordinator() -> ContentDisplayHandler {
        ContentDisplayHandler(manager: manager)
    }
}

extension ContentDisplayHandler {
    @objc func handleEdgeSwipe(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        if recognizer.state == .ended {
            guard let currentView = recognizer.view as? WKWebView else { return }
            if currentView.canGoBack {
                currentView.goBack()
            } else if let latestAddition = statsManager.additionalDisplays.last, currentView == latestAddition {
                statsManager.removeAdditions(currentPath: nil)
            }
        }
    }
}

struct ChickInterface: View {
    
    @State var displayPath: String = ""
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if let pathUrl = URL(string: displayPath) {
                MainDisplayWrapper(
                    destinationPath: pathUrl
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            displayPath = UserDefaults.standard.string(forKey: "temp_path") ?? (UserDefaults.standard.string(forKey: "saved_path") ?? "")
            if let tempPath = UserDefaults.standard.string(forKey: "temp_path"), !tempPath.isEmpty {
                UserDefaults.standard.set(nil, forKey: "temp_path")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LoadTempPath"))) { _ in
            if let tempPath = UserDefaults.standard.string(forKey: "temp_path"), !tempPath.isEmpty {
                displayPath = tempPath
                UserDefaults.standard.set(nil, forKey: "temp_path")
            }
        }
    }
}

class ChickLauncher: ObservableObject {
    @Published var activeView: DisplayPhase = .hatching
    @Published var displayPath: URL?
    @Published var showPrompt = false
    
    private var trackingData: [AnyHashable: Any] = [:]
    private var initialLaunch: Bool {
        !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    }
    
    enum DisplayPhase {
        case hatching
        case statsDisplay
        case nestFallback
        case strayOffline
    }
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleTrackingData(_:)), name: NSNotification.Name("ConversionDataReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleTrackingError(_:)), name: NSNotification.Name("ConversionDataFailed"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateToken(_:)), name: NSNotification.Name("FCMTokenUpdated"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(retrySetup), name: NSNotification.Name("RetryConfig"), object: nil)
        
        checkConnectionAndProceed()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func checkConnectionAndProceed() {
        let connectionChecker = NWPathMonitor()
        connectionChecker.pathUpdateHandler = { status in
            DispatchQueue.main.async {
                if status.status != .satisfied {
                    self.handleNoConnection()
                }
            }
        }
        connectionChecker.start(queue: DispatchQueue.global())
    }
    
    @objc private func handleTrackingData(_ notification: Notification) {
        trackingData = (notification.userInfo ?? [:])["conversionData"] as? [AnyHashable: Any] ?? [:]
        processTrackingData()
    }
    
    @objc private func handleTrackingError(_ notification: Notification) {
        handleSetupError()
    }
    
    @objc private func updateToken(_ notification: Notification) {
        if let tokenStr = notification.object as? String {
            UserDefaults.standard.set(tokenStr, forKey: "push_token")
            performSetupQuery()
        }
    }
    
    @objc private func handlePushPath(_ notification: Notification) {
        guard let details = notification.userInfo as? [String: Any],
              let pathStr = details["tempUrl"] as? String else {
            return
        }
        
        DispatchQueue.main.async {
            self.displayPath = URL(string: pathStr)!
            self.activeView = .statsDisplay
        }
    }
    
    @objc private func retrySetup() {
        checkConnectionAndProceed()
    }
    
    private func processTrackingData() {
//        guard !trackingData.isEmpty else {
//            return
//        }
        if UserDefaults.standard.string(forKey: "chick_mode") == "Nest" {
            DispatchQueue.main.async {
                self.activeView = .nestFallback
            }
            return
        }
        
//        if initialLaunch {
//            if let origin = trackingData["af_status"] as? String, origin == "Organic" {
//                self.switchToFallback()
//                return
//            }
//        }
        
        if let tempPath = UserDefaults.standard.string(forKey: "temp_path"), !tempPath.isEmpty {
            displayPath = URL(string: tempPath)
            self.activeView = .statsDisplay
            return
        }
        
        if displayPath == nil {
            if !UserDefaults.standard.bool(forKey: "allowed_alerts") && !UserDefaults.standard.bool(forKey: "denied_alerts") {
                checkAndShowPrompt()
            } else {
                performSetupQuery()
            }
        }
    }
    
    func performSetupQuery() {
        guard let configEndpoint = URL(string: "https://chiickstats.com/config.php") else {
            handleSetupError()
            return
        }
        
        var configReq = URLRequest(url: configEndpoint)
        configReq.httpMethod = "POST"
        configReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var dataPayload = trackingData
        dataPayload["af_id"] = AppsFlyerLib.shared().getAppsFlyerUID()
        dataPayload["bundle_id"] = Bundle.main.bundleIdentifier ?? "com.example.app"
        dataPayload["os"] = "iOS"
        dataPayload["store_id"] = "id6753870535"
        dataPayload["locale"] = Locale.preferredLanguages.first?.prefix(2).uppercased() ?? "EN"
        dataPayload["push_token"] = UserDefaults.standard.string(forKey: "push_token") ?? Messaging.messaging().fcmToken
        dataPayload["firebase_project_id"] = FirebaseApp.app()?.options.gcmSenderID
        
        do {
            configReq.httpBody = try JSONSerialization.data(withJSONObject: dataPayload)
        } catch {
            handleSetupError()
            return
        }
        
        URLSession.shared.dataTask(with: configReq) { rawData, rawResp, issue in
            DispatchQueue.main.async {
                if let _ = issue {
                    self.handleSetupError()
                    return
                }
                
                guard let httpRawResp = rawResp as? HTTPURLResponse, httpRawResp.statusCode == 200,
                      let rawData = rawData else {
                    self.handleSetupError()
                    return
                }
                
                do {
                    if let parsedJson = try JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
                        if let isValid = parsedJson["ok"] as? Bool, isValid {
                            if let pathStr = parsedJson["url"] as? String, let validUntil = parsedJson["expires"] as? TimeInterval {
                                func dsadasjnd() {
                                    UserDefaults.standard.set(pathStr, forKey: "saved_path")
                                    UserDefaults.standard.set(validUntil, forKey: "saved_expires")
                                    UserDefaults.standard.set("StatsDisplay", forKey: "chick_mode")
                                    UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                                }
                                dsadasjnd()
                                self.displayPath = URL(string: pathStr)
                                self.activeView = .statsDisplay
                            }
                        } else {
                            self.switchToFallback()
                        }
                    }
                } catch {
                    self.handleSetupError()
                }
            }
        }.resume()
    }
    
    private func handleSetupError() {
        if let cachedPath = UserDefaults.standard.string(forKey: "saved_path"), let validPath = URL(string: cachedPath) {
            displayPath = validPath
            activeView = .statsDisplay
        } else {
            switchToFallback()
        }
    }
    
    private func switchToFallback() {
        UserDefaults.standard.set("Nest", forKey: "chick_mode")
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        DispatchQueue.main.async {
            self.activeView = .nestFallback
        }
    }
    
    private func handleNoConnection() {
        let currentMode = UserDefaults.standard.string(forKey: "chick_mode")
        if currentMode == "StatsDisplay" {
            DispatchQueue.main.async {
                self.activeView = .strayOffline
            }
        } else {
            switchToFallback()
        }
    }
    
    private func checkAndShowPrompt() {
        if let lastPrompt = UserDefaults.standard.value(forKey: "last_alert_prompt") as? Date,
           Date().timeIntervalSince(lastPrompt) < 259200 {
            performSetupQuery()
            return
        }
        showPrompt = true
    }
    
    func requestAlertAccess() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, issue in
            DispatchQueue.main.async {
                if granted {
                    UserDefaults.standard.set(true, forKey: "allowed_alerts")
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    UserDefaults.standard.set(false, forKey: "allowed_alerts")
                    UserDefaults.standard.set(true, forKey: "denied_alerts")
                }
                self.performSetupQuery()
                self.showPrompt = false
                if let issue = issue {
                    print("Permission request failed: \(issue)")
                }
            }
        }
    }
}

struct AlertPromptScreen: View {
    var acceptAction: () -> Void
    var declineAction: () -> Void
    
    var body: some View {
        GeometryReader { layout in
            let isHorizontal = layout.size.width > layout.size.height
            
            ZStack {
                if isHorizontal {
                    Image("chcik_stats_splash_back_land")
                        .resizable()
                        .scaledToFill()
                        .frame(width: layout.size.width, height: layout.size.height)
                        .ignoresSafeArea()
                } else {
                    Image("chick_stats_splash_back")
                        .resizable()
                        .scaledToFill()
                        .frame(width: layout.size.width, height: layout.size.height)
                        .ignoresSafeArea()
                }
                
                VStack(spacing: isHorizontal ? 5 : 10) {
                    Spacer()
                    
                    Text("Allow notifications about bonuses and promos".uppercased())
                        .font(.custom("AlfaSlabOne-Regular", size: 20))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                    
                    Text("Stay tuned with best offers from our casino")
                        .font(.custom("AlfaSlabOne-Regular", size: 15))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color.init(red: 186/255, green: 186/255, blue: 186/255))
                        .padding(.horizontal, 52)
                        .padding(.top, 4)
                    
                    Button(action: acceptAction) {
                        Image("bonus_btn")
                            .resizable()
                            .frame(height: 60)
                    }
                    .frame(width: 350)
                    .padding(.top, 24)
                    
                    Button(action: declineAction) {
                        Text("SKIP")
                            .font(.custom("AlfaSlabOne-Regular", size: 15))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color.init(red: 186/255, green: 186/255, blue: 186/255))
                    }
                    
                    Spacer()
                        .frame(height: isHorizontal ? 30 : 70)
                }
                .padding(.horizontal, isHorizontal ? 20 : 0)
            }
            
        }
        .ignoresSafeArea()
    }
}

struct ChickLaunchInterface: View {
    
    @StateObject private var launcher = ChickLauncher()
    
    @State private var isHatching = false
    
    var body: some View {
        ZStack {
            if launcher.activeView == .hatching || launcher.showPrompt {
                hatchingScreen
            }
            
            if launcher.showPrompt {
                AlertPromptScreen(
                    acceptAction: {
                        launcher.requestAlertAccess()
                    },
                    declineAction: {
                        UserDefaults.standard.set(Date(), forKey: "last_alert_prompt")
                        launcher.showPrompt = false
                        launcher.performSetupQuery()
                    }
                )
            } else {
                switch launcher.activeView {
                case .hatching:
                    EmptyView()
                case .statsDisplay:
                    if let _ = launcher.displayPath {
                        ChickInterface()
                    } else {
                        ContentView()
                            .preferredColorScheme(.dark)
                            .accentColor(.accentYellow)
                            .font(.bodyText)
                    }
                case .nestFallback:
                    ContentView()
                        .preferredColorScheme(.dark)
                        .accentColor(.accentYellow)
                        .font(.bodyText)
                case .strayOffline:
                    strayScreen
                }
            }
        }
    }
    
    private var hatchingScreen: some View {
        GeometryReader { layout in
            let isHorizontal = layout.size.width > layout.size.height
            
            ZStack {
                
                if isHorizontal {
                    Image("chcik_stats_splash_back_land")
                        .resizable()
                        .scaledToFill()
                        .frame(width: layout.size.width, height: layout.size.height)
                        .ignoresSafeArea()
                } else {
                    Image("chick_stats_splash_back")
                        .resizable()
                        .scaledToFill()
                        .frame(width: layout.size.width, height: layout.size.height)
                        .ignoresSafeArea()
                }
                
                VStack {
                    Spacer()
                    
                    Text("LOADING APP...")
                        .font(.custom("AlfaSlabOne-Regular", size: 24))
                        .foregroundColor(.white)
                    
                    Image("pero")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .rotationEffect(animating ? .degrees(0) : .degrees(-50))
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animating)
                    
                    Spacer()
                        .frame(height: 70)
                }
                .onAppear {
                    animating = true
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            isHatching = true
        }
    }
    
    @State var animating = false
    
    private var strayScreen: some View {
        GeometryReader { layout in
            let isHorizontal = layout.size.width > layout.size.height
            
            ZStack {
                
                if isHorizontal {
                    Image("chcik_stats_splash_back_land")
                        .resizable()
                        .scaledToFill()
                        .frame(width: layout.size.width, height: layout.size.height)
                        .ignoresSafeArea()
                } else {
                    Image("chick_stats_splash_back")
                        .resizable()
                        .scaledToFill()
                        .frame(width: layout.size.width, height: layout.size.height)
                        .ignoresSafeArea()
                }
                
                VStack {
                    Spacer() 
                    Text("NO INTERNET CONNECTION! CHECK INTERNET CONNECTION AND RETURN!")
                        .font(.custom("AlfaSlabOne-Regular", size: 18))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(
                            Rectangle()
                                .fill(Color.init(red: 143/255, green: 76/255, blue: 22/255))
                        )
                        .padding(.horizontal, 24)
                    Spacer().frame(height: 100)
                }
            }
            
        }
        .ignoresSafeArea()
    }
    
}
