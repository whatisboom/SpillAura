import Foundation

/// The 8 built-in vibes shipped with SpillAura.
///
/// Fixed UUIDs ensure stable identity across launches so user selections persist.
enum BuiltinVibes {

    static let all: [Vibe] = [
        warmSunset, neon, ocean, forest, candy, fire, galaxy, disco
    ]

    static let warmSunset = Vibe(
        id: UUID(uuidString: "00000001-0000-0000-0000-000000000000")!,
        name: "Warm Sunset",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.00, green: 0.42, blue: 0.00),  // deep orange
            CodableColor(red: 1.00, green: 0.65, blue: 0.00),  // gold
            CodableColor(red: 1.00, green: 0.84, blue: 0.10),  // amber
            CodableColor(red: 1.00, green: 0.55, blue: 0.10),  // warm orange
        ],
        speed: 0.12,
        pattern: .cycle,
        channelOffset: 0.15
    )

    static let neon = Vibe(
        id: UUID(uuidString: "00000002-0000-0000-0000-000000000000")!,
        name: "Neon",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.00, green: 0.00, blue: 0.70),  // hot pink
            CodableColor(red: 0.00, green: 0.90, blue: 1.00),  // cyan
            CodableColor(red: 1.00, green: 1.00, blue: 0.00),  // yellow
        ],
        speed: 0.40,
        pattern: .cycle,
        channelOffset: 0.33
    )

    static let ocean = Vibe(
        id: UUID(uuidString: "00000003-0000-0000-0000-000000000000")!,
        name: "Ocean",
        type: .dynamic,
        palette: [
            CodableColor(red: 0.00, green: 0.30, blue: 0.80),  // deep blue
            CodableColor(red: 0.00, green: 0.70, blue: 0.90),  // ocean blue
            CodableColor(red: 0.20, green: 0.90, blue: 0.90),  // aqua
            CodableColor(red: 0.90, green: 1.00, blue: 1.00),  // white foam
        ],
        speed: 0.15,
        pattern: .bounce,
        channelOffset: 0.25
    )

    static let forest = Vibe(
        id: UUID(uuidString: "00000004-0000-0000-0000-000000000000")!,
        name: "Forest",
        type: .dynamic,
        palette: [
            CodableColor(red: 0.00, green: 0.25, blue: 0.05),  // dark green
            CodableColor(red: 0.20, green: 0.65, blue: 0.10),  // leaf green
            CodableColor(red: 0.55, green: 0.90, blue: 0.20),  // lime
        ],
        speed: 0.10,
        pattern: .bounce,
        channelOffset: 0.20
    )

    static let candy = Vibe(
        id: UUID(uuidString: "00000005-0000-0000-0000-000000000000")!,
        name: "Candy",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.00, green: 0.40, blue: 0.70),  // pink
            CodableColor(red: 0.70, green: 0.20, blue: 1.00),  // purple
            CodableColor(red: 0.30, green: 0.50, blue: 1.00),  // periwinkle
        ],
        speed: 0.25,
        pattern: .cycle,
        channelOffset: 0.33
    )

    static let fire = Vibe(
        id: UUID(uuidString: "00000006-0000-0000-0000-000000000000")!,
        name: "Fire",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.00, green: 0.00, blue: 0.00),  // red
            CodableColor(red: 1.00, green: 0.40, blue: 0.00),  // orange
            CodableColor(red: 1.00, green: 0.85, blue: 0.00),  // yellow
        ],
        speed: 0.50,
        pattern: .bounce,
        channelOffset: 0.20
    )

    static let galaxy = Vibe(
        id: UUID(uuidString: "00000007-0000-0000-0000-000000000000")!,
        name: "Galaxy",
        type: .dynamic,
        palette: [
            CodableColor(red: 0.20, green: 0.00, blue: 0.40),  // deep purple
            CodableColor(red: 0.10, green: 0.10, blue: 0.60),  // indigo
            CodableColor(red: 0.00, green: 0.40, blue: 0.50),  // teal
            CodableColor(red: 0.05, green: 0.05, blue: 0.30),  // navy
        ],
        speed: 0.08,
        pattern: .cycle,
        channelOffset: 0.25
    )

    static let disco = Vibe(
        id: UUID(uuidString: "00000008-0000-0000-0000-000000000000")!,
        name: "Disco",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.00, green: 0.00, blue: 0.00),  // red
            CodableColor(red: 1.00, green: 0.50, blue: 0.00),  // orange
            CodableColor(red: 1.00, green: 1.00, blue: 0.00),  // yellow
            CodableColor(red: 0.00, green: 1.00, blue: 0.00),  // green
            CodableColor(red: 0.00, green: 0.50, blue: 1.00),  // blue
            CodableColor(red: 0.70, green: 0.00, blue: 1.00),  // purple
        ],
        speed: 0.80,
        pattern: .cycle,
        channelOffset: 0.17
    )
}
