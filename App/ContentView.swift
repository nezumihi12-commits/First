import SwiftUI

struct ContentView: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("わたしの自作アプリ")
                .font(.largeTitle.bold())

            Text("\(count)")
                .font(.system(size: 72, weight: .semibold, design: .rounded))

            Button("増やす") {
                count += 1
            }
            .buttonStyle(.borderedProminent)

            Button("リセット") {
                count = 0
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
