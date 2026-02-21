import Foundation

/// The 8 built-in auras shipped with SpillAura.
///
/// Fixed UUIDs ensure stable identity across launches so user selections persist.
public enum BuiltinAuras {

    public static let all: [Aura] = [
        disco, neon, fire, warmSunset, forest, ocean, galaxy, candy
    ]

    public static let warmSunset = Aura(
        id: UUID(uuidString: "00000001-0000-0000-0000-000000000000")!,
        name: "Warm Sunset",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.00, green: 0.42, blue: 0.00),
            CodableColor(red: 1.00, green: 0.65, blue: 0.00),
            CodableColor(red: 1.00, green: 0.84, blue: 0.10),
            CodableColor(red: 1.00, green: 0.55, blue: 0.10),
        ],
        speed: 0.12,
        pattern: .cycle,
        channelOffset: 0.15
    )

    public static let neon = Aura(
        id: UUID(uuidString: "00000002-0000-0000-0000-000000000000")!,
        name: "Neon",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.00, green: 0.00, blue: 0.70),
            CodableColor(red: 0.00, green: 0.90, blue: 1.00),
            CodableColor(red: 1.00, green: 1.00, blue: 0.00),
        ],
        speed: 0.40,
        pattern: .cycle,
        channelOffset: 0.33
    )

    public static let ocean = Aura(
        id: UUID(uuidString: "00000003-0000-0000-0000-000000000000")!,
        name: "Ocean",
        type: .dynamic,
        palette: [
            CodableColor(red: 0.00, green: 0.30, blue: 0.80),
            CodableColor(red: 0.00, green: 0.70, blue: 0.90),
            CodableColor(red: 0.20, green: 0.90, blue: 0.90),
            CodableColor(red: 0.90, green: 1.00, blue: 1.00),
        ],
        speed: 0.15,
        pattern: .bounce,
        channelOffset: 0.25
    )

    public static let forest = Aura(
        id: UUID(uuidString: "00000004-0000-0000-0000-000000000000")!,
        name: "Forest",
        type: .dynamic,
        palette: [
            CodableColor(red: 0.00, green: 0.25, blue: 0.05),
            CodableColor(red: 0.20, green: 0.65, blue: 0.10),
            CodableColor(red: 0.55, green: 0.90, blue: 0.20),
        ],
        speed: 0.10,
        pattern: .bounce,
        channelOffset: 0.20
    )

    public static let candy = Aura(
        id: UUID(uuidString: "00000005-0000-0000-0000-000000000000")!,
        name: "Candy",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.00, green: 0.40, blue: 0.70),
            CodableColor(red: 0.70, green: 0.20, blue: 1.00),
            CodableColor(red: 0.30, green: 0.50, blue: 1.00),
        ],
        speed: 0.25,
        pattern: .cycle,
        channelOffset: 0.33
    )

    public static let fire = Aura(
        id: UUID(uuidString: "00000006-0000-0000-0000-000000000000")!,
        name: "Fire",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.00, green: 0.00, blue: 0.00),
            CodableColor(red: 1.00, green: 0.40, blue: 0.00),
            CodableColor(red: 1.00, green: 0.85, blue: 0.00),
        ],
        speed: 0.50,
        pattern: .bounce,
        channelOffset: 0.20
    )

    public static let galaxy = Aura(
        id: UUID(uuidString: "00000007-0000-0000-0000-000000000000")!,
        name: "Galaxy",
        type: .dynamic,
        palette: [
            CodableColor(red: 0.20, green: 0.00, blue: 0.40),
            CodableColor(red: 0.10, green: 0.10, blue: 0.60),
            CodableColor(red: 0.00, green: 0.40, blue: 0.50),
            CodableColor(red: 0.05, green: 0.05, blue: 0.30),
        ],
        speed: 0.08,
        pattern: .cycle,
        channelOffset: 0.25
    )

    public static let disco = Aura(
        id: UUID(uuidString: "00000008-0000-0000-0000-000000000000")!,
        name: "Disco",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.00, green: 0.00, blue: 0.00),
            CodableColor(red: 1.00, green: 0.50, blue: 0.00),
            CodableColor(red: 1.00, green: 1.00, blue: 0.00),
            CodableColor(red: 0.00, green: 1.00, blue: 0.00),
            CodableColor(red: 0.00, green: 0.50, blue: 1.00),
            CodableColor(red: 0.70, green: 0.00, blue: 1.00),
        ],
        speed: 0.80,
        pattern: .cycle,
        channelOffset: 0.17
    )
}
