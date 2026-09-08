import AppKit

@main
enum TinyStatusMain {
    static func main() {
        let argv = CommandLine.arguments
        let name = URL(fileURLWithPath: argv[0]).lastPathComponent
        let rest = Array(argv.dropFirst())
        let gui = rest.contains("--gui")
        let asCLI = !gui && (
            name == "tiny-status"
                || rest.first == "cli"
                || rest.first == "--cli"
                || (rest.first.map { CLI.commands.contains($0) } ?? false)
        )
        if asCLI {
            let args: [String] = {
                if rest.first == "cli" || rest.first == "--cli" { return Array(rest.dropFirst()) }
                return rest
            }()
            CLI.run(args.isEmpty ? ["help"] : args)
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
