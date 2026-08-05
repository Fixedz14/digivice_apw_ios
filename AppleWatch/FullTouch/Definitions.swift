import Foundation

struct GameCatalog: Codable {
    let digimon: [DigimonDefinition]
    let characters: [CharacterDefinition]
    let areas: [AreaDefinition]
    let spirits: [SpiritDefinition]

    static func load() -> GameCatalog {
        guard
            let url = Bundle.main.url(forResource: "game_catalog", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(GameCatalog.self, from: data)
        else {
            return .fallback
        }
        return catalog
    }

    static let fallback = GameCatalog(
        digimon: [],
        characters: CharacterDefinition.defaults,
        areas: AreaDefinition.defaults,
        spirits: SpiritDefinition.defaults
    )
}

struct DigimonDefinition: Codable, Identifiable, Hashable {
    let id: Int
    let sprite: String
    let number: Int
    let name: String
    let level: Int
    let hp: Int
    let element: Int
    let energy: Int
    let crunch: Int
    let ability: Int
    let code: String?
    let type: String
    let evolution: Int?
    let unlock: Bool

    var displayName: String {
        name.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    var isEncounterEligible: Bool {
        !["spirit", "boss", "ancient", "final_boss"].contains(type)
            && ![96, 97, 98, 99].contains(id)
    }

    var isSpiritForm: Bool {
        type == "spirit" || type == "ancient"
    }
}

struct CharacterDefinition: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let sprite: String
    let baseHP: Int
    let baseSpirit: Int
    let baseStamina: Int
    let baseSkill: Int
    let capHP: Int
    let capSpirit: Int
    let capStamina: Int
    let capSkill: Int
    let humanSpiritID: Int
    let beastSpiritID: Int

    static let defaults: [CharacterDefinition] = [
        .init(id: 0, name: "TAKUYA", sprite: "spr_takuya", baseHP: 6, baseSpirit: 5, baseStamina: 5, baseSkill: 7, capHP: 210, capSpirit: 175, capStamina: 160, capSkill: 170, humanSpiritID: 100, beastSpiritID: 101),
        .init(id: 1, name: "KOJI", sprite: "spr_koji", baseHP: 6, baseSpirit: 7, baseStamina: 5, baseSkill: 5, capHP: 210, capSpirit: 160, capStamina: 160, capSkill: 185, humanSpiritID: 102, beastSpiritID: 103),
        .init(id: 2, name: "JP", sprite: "spr_jp", baseHP: 8, baseSpirit: 4, baseStamina: 8, baseSkill: 5, capHP: 240, capSpirit: 195, capStamina: 150, capSkill: 180, humanSpiritID: 104, beastSpiritID: 105),
        .init(id: 3, name: "ZOE", sprite: "spr_zoe", baseHP: 5, baseSpirit: 5, baseStamina: 4, baseSkill: 7, capHP: 185, capSpirit: 150, capStamina: 190, capSkill: 165, humanSpiritID: 106, beastSpiritID: 107),
        .init(id: 4, name: "TOMMY", sprite: "spr_tommy", baseHP: 5, baseSpirit: 7, baseStamina: 5, baseSkill: 4, capHP: 100, capSpirit: 180, capStamina: 140, capSkill: 180, humanSpiritID: 108, beastSpiritID: 109),
        .init(id: 5, name: "KOICHI", sprite: "spr_koichi", baseHP: 6, baseSpirit: 5, baseStamina: 5, baseSkill: 7, capHP: 110, capSpirit: 185, capStamina: 160, capSkill: 160, humanSpiritID: 110, beastSpiritID: 111)
    ]
}

struct AreaDefinition: Codable, Identifiable, Hashable {
    let id: Int
    let map: Int
    let slot: Int
    let name: String
    let distance: Int
    let bossPrimary: Int?
    let bossUpgradeDependencyArea: Int?
    let bossUpgraded: Int?

    static let defaults: [AreaDefinition] = {
        let distances = [6000, 8000, 7000, 9000, 10000, 11000, 9000, 7000, 10000, 11000, 10000, 10000, 12000]
        let bosses: [(Int?, Int?, Int?)] = [
            (131, 9, 132), (96, nil, nil), (133, 6, 134),
            (135, 10, 136), (137, 7, 119), (98, nil, nil),
            (133, 2, 134), (137, 4, 138), (97, nil, nil),
            (131, 0, 132), (135, 3, 136), (99, nil, nil),
            (120, nil, 127)
        ]
        return distances.indices.map { index in
            AreaDefinition(
                id: index,
                map: min(4, index / 3),
                slot: index % 3,
                name: index == 12 ? "FINAL AREA" : "AREA \(String(format: "%02d", index + 1))",
                distance: distances[index],
                bossPrimary: bosses[index].0,
                bossUpgradeDependencyArea: bosses[index].1,
                bossUpgraded: bosses[index].2
            )
        }
    }()
}

struct SpiritDefinition: Codable, Identifiable, Hashable {
    let id: Int
    let ownerCharacterID: Int
    let kind: String
    let digimonID: Int
    let requiredSpiritIDs: [Int]

    static let defaults: [SpiritDefinition] = {
        var values = [SpiritDefinition]()
        for characterID in 0..<6 {
            values.append(.init(id: characterID * 2, ownerCharacterID: characterID, kind: "human", digimonID: 100 + characterID * 2, requiredSpiritIDs: []))
            values.append(.init(id: characterID * 2 + 1, ownerCharacterID: characterID, kind: "beast", digimonID: 101 + characterID * 2, requiredSpiritIDs: []))
        }
        return values
    }()
}

struct CharacterStats: Codable, Hashable {
    var hp: Int
    var spirit: Int
    var stamina: Int
    var skill: Int

    static func initial(from definition: CharacterDefinition) -> CharacterStats {
        .init(
            hp: definition.baseHP,
            spirit: definition.baseSpirit,
            stamina: definition.baseStamina,
            skill: definition.baseSkill
        )
    }
}

enum ElementKind: Int, CaseIterable {
    case fire = 0
    case light = 1
    case wind = 2
    case thunder = 3
    case ice = 4
    case darkness = 5
    case earth = 6
    case wood = 7
    case steel = 8
    case water = 9

    var name: String {
        switch self {
        case .fire: "FIRE"
        case .light: "LIGHT"
        case .wind: "WIND"
        case .thunder: "THUNDER"
        case .ice: "ICE"
        case .darkness: "DARK"
        case .earth: "EARTH"
        case .wood: "WOOD"
        case .steel: "STEEL"
        case .water: "WATER"
        }
    }
}

