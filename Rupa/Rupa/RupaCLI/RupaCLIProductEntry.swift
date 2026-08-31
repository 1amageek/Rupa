import RupaCLIComposition

@main
struct RupaCLIProductEntry {
    static func main() async {
        await RupaCLIComposition.run()
    }
}
