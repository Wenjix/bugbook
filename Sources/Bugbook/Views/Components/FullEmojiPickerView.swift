import SwiftUI
import AppKit

// MARK: - Emoji Data

struct EmojiItem: Identifiable, Equatable {
    let id: String
    let emoji: String
    let keywords: [String]

    init(_ emoji: String, keywords: [String] = []) {
        self.id = emoji
        self.emoji = emoji
        self.keywords = keywords
    }
}

enum EmojiCategory: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case all = "All"
    case smileys = "Smileys"
    case gestures = "Gestures"
    case hearts = "Hearts"
    case nature = "Nature"
    case animals = "Animals"
    case food = "Food"
    case activities = "Activities"
    case travel = "Travel"
    case objects = "Objects"
    case symbols = "Symbols"
    case flags = "Flags"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .recent: return "clock"
        case .all: return "square.grid.3x3.fill"
        case .smileys: return "face.smiling"
        case .gestures: return "hand.raised"
        case .hearts: return "heart"
        case .nature: return "leaf"
        case .animals: return "pawprint"
        case .food: return "fork.knife"
        case .activities: return "sportscourt"
        case .travel: return "car"
        case .objects: return "lightbulb"
        case .symbols: return "number"
        case .flags: return "flag"
        }
    }
}

struct EmojiData {
    static let categories: [(EmojiCategory, [EmojiItem])] = [
        (.smileys, smileys),
        (.gestures, gestures),
        (.hearts, hearts),
        (.nature, nature),
        (.animals, animals),
        (.food, food),
        (.activities, activities),
        (.travel, travel),
        (.objects, objects),
        (.symbols, symbols),
        (.flags, flags),
    ]

    static let smileys: [EmojiItem] = [
        EmojiItem("\u{1F600}", keywords: ["grinning", "happy", "smile"]),
        EmojiItem("\u{1F603}", keywords: ["smiley", "happy"]),
        EmojiItem("\u{1F604}", keywords: ["smile", "happy", "joy"]),
        EmojiItem("\u{1F601}", keywords: ["grin", "happy"]),
        EmojiItem("\u{1F606}", keywords: ["laughing", "satisfied"]),
        EmojiItem("\u{1F605}", keywords: ["sweat", "smile"]),
        EmojiItem("\u{1F923}", keywords: ["rofl", "laughing"]),
        EmojiItem("\u{1F602}", keywords: ["joy", "tears", "laughing"]),
        EmojiItem("\u{1F642}", keywords: ["slightly", "smile"]),
        EmojiItem("\u{1F643}", keywords: ["upside", "down"]),
        EmojiItem("\u{1FAE0}", keywords: ["melting"]),
        EmojiItem("\u{1F609}", keywords: ["wink"]),
        EmojiItem("\u{1F60A}", keywords: ["blush", "happy"]),
        EmojiItem("\u{1F607}", keywords: ["innocent", "angel", "halo"]),
        EmojiItem("\u{1F970}", keywords: ["love", "hearts", "face"]),
        EmojiItem("\u{1F60D}", keywords: ["heart", "eyes", "love"]),
        EmojiItem("\u{1F929}", keywords: ["star", "struck"]),
        EmojiItem("\u{1F618}", keywords: ["kiss", "blowing"]),
        EmojiItem("\u{1F617}", keywords: ["kissing"]),
        EmojiItem("\u{1F61A}", keywords: ["kissing", "closed", "eyes"]),
        EmojiItem("\u{1F619}", keywords: ["kissing", "smile"]),
        EmojiItem("\u{1F60B}", keywords: ["yum", "delicious", "tongue"]),
        EmojiItem("\u{1F61B}", keywords: ["tongue", "out"]),
        EmojiItem("\u{1F61C}", keywords: ["wink", "tongue"]),
        EmojiItem("\u{1F92A}", keywords: ["zany", "crazy"]),
        EmojiItem("\u{1F61D}", keywords: ["tongue", "squint"]),
        EmojiItem("\u{1F911}", keywords: ["money", "mouth"]),
        EmojiItem("\u{1F917}", keywords: ["hugs", "hugging"]),
        EmojiItem("\u{1F92D}", keywords: ["shush", "hand", "mouth"]),
        EmojiItem("\u{1F92B}", keywords: ["shushing", "quiet"]),
        EmojiItem("\u{1F914}", keywords: ["thinking", "hmm"]),
        EmojiItem("\u{1F910}", keywords: ["zipper", "mouth", "quiet"]),
        EmojiItem("\u{1F928}", keywords: ["raised", "eyebrow"]),
        EmojiItem("\u{1F610}", keywords: ["neutral", "face"]),
        EmojiItem("\u{1F611}", keywords: ["expressionless"]),
        EmojiItem("\u{1F636}", keywords: ["no", "mouth", "silent"]),
        EmojiItem("\u{1F60F}", keywords: ["smirk"]),
        EmojiItem("\u{1F612}", keywords: ["unamused"]),
        EmojiItem("\u{1F644}", keywords: ["eye", "roll"]),
        EmojiItem("\u{1F62C}", keywords: ["grimace"]),
        EmojiItem("\u{1F925}", keywords: ["lying", "pinocchio"]),
        EmojiItem("\u{1F60C}", keywords: ["relieved"]),
        EmojiItem("\u{1F614}", keywords: ["pensive", "sad"]),
        EmojiItem("\u{1F62A}", keywords: ["sleepy"]),
        EmojiItem("\u{1F924}", keywords: ["drooling"]),
        EmojiItem("\u{1F634}", keywords: ["sleeping", "zzz"]),
        EmojiItem("\u{1F637}", keywords: ["mask", "sick"]),
        EmojiItem("\u{1F912}", keywords: ["thermometer", "sick"]),
        EmojiItem("\u{1F915}", keywords: ["bandage", "hurt"]),
        EmojiItem("\u{1F922}", keywords: ["nauseated", "sick"]),
        EmojiItem("\u{1F92E}", keywords: ["vomiting"]),
        EmojiItem("\u{1F927}", keywords: ["sneezing"]),
        EmojiItem("\u{1F975}", keywords: ["hot", "sweating"]),
        EmojiItem("\u{1F976}", keywords: ["cold", "freezing"]),
        EmojiItem("\u{1F974}", keywords: ["woozy", "dizzy"]),
        EmojiItem("\u{1F635}", keywords: ["dizzy"]),
        EmojiItem("\u{1F92F}", keywords: ["mind", "blown", "exploding"]),
        EmojiItem("\u{1F920}", keywords: ["cowboy"]),
        EmojiItem("\u{1F973}", keywords: ["party", "celebration"]),
        EmojiItem("\u{1F978}", keywords: ["disguise"]),
        EmojiItem("\u{1F60E}", keywords: ["sunglasses", "cool"]),
        EmojiItem("\u{1F913}", keywords: ["nerd", "glasses"]),
        EmojiItem("\u{1F9D0}", keywords: ["monocle"]),
        EmojiItem("\u{1F615}", keywords: ["confused"]),
        EmojiItem("\u{1FAE4}", keywords: ["dotted", "line"]),
        EmojiItem("\u{1F61F}", keywords: ["worried"]),
        EmojiItem("\u{1F641}", keywords: ["slightly", "frown"]),
        EmojiItem("\u{1F62E}", keywords: ["open", "mouth"]),
        EmojiItem("\u{1F62F}", keywords: ["hushed"]),
        EmojiItem("\u{1F632}", keywords: ["astonished"]),
        EmojiItem("\u{1F633}", keywords: ["flushed"]),
        EmojiItem("\u{1F97A}", keywords: ["pleading", "puppy"]),
        EmojiItem("\u{1F979}", keywords: ["holding", "back", "tears"]),
        EmojiItem("\u{1F626}", keywords: ["frowning"]),
        EmojiItem("\u{1F627}", keywords: ["anguished"]),
        EmojiItem("\u{1F628}", keywords: ["fearful"]),
        EmojiItem("\u{1F630}", keywords: ["anxious", "sweat"]),
        EmojiItem("\u{1F625}", keywords: ["sad", "relieved"]),
        EmojiItem("\u{1F622}", keywords: ["cry", "sad"]),
        EmojiItem("\u{1F62D}", keywords: ["sobbing", "crying"]),
        EmojiItem("\u{1F631}", keywords: ["scream", "scared"]),
        EmojiItem("\u{1F616}", keywords: ["confounded"]),
        EmojiItem("\u{1F623}", keywords: ["persevere"]),
        EmojiItem("\u{1F61E}", keywords: ["disappointed"]),
        EmojiItem("\u{1F613}", keywords: ["sweat"]),
        EmojiItem("\u{1F629}", keywords: ["weary"]),
        EmojiItem("\u{1F62B}", keywords: ["tired"]),
        EmojiItem("\u{1F971}", keywords: ["yawning"]),
        EmojiItem("\u{1F624}", keywords: ["triumph", "steam"]),
        EmojiItem("\u{1F621}", keywords: ["rage", "angry"]),
        EmojiItem("\u{1F620}", keywords: ["angry"]),
        EmojiItem("\u{1F92C}", keywords: ["cursing", "swearing"]),
        EmojiItem("\u{1F608}", keywords: ["smiling", "devil"]),
        EmojiItem("\u{1F47F}", keywords: ["angry", "devil"]),
        EmojiItem("\u{1F480}", keywords: ["skull", "death"]),
        EmojiItem("\u{2620}\u{FE0F}", keywords: ["skull", "crossbones"]),
        EmojiItem("\u{1F4A9}", keywords: ["poop"]),
        EmojiItem("\u{1F921}", keywords: ["clown"]),
        EmojiItem("\u{1F47B}", keywords: ["ghost"]),
        EmojiItem("\u{1F47D}", keywords: ["alien"]),
        EmojiItem("\u{1F47E}", keywords: ["alien", "monster"]),
        EmojiItem("\u{1F916}", keywords: ["robot"]),
    ]

    static let gestures: [EmojiItem] = [
        EmojiItem("\u{1F44B}", keywords: ["wave", "hello", "bye"]),
        EmojiItem("\u{1F91A}", keywords: ["raised", "back", "hand"]),
        EmojiItem("\u{1F590}\u{FE0F}", keywords: ["fingers", "splayed"]),
        EmojiItem("\u{270B}", keywords: ["raised", "hand", "stop"]),
        EmojiItem("\u{1F596}", keywords: ["vulcan", "spock"]),
        EmojiItem("\u{1FAF1}", keywords: ["rightward", "push"]),
        EmojiItem("\u{1FAF2}", keywords: ["leftward", "push"]),
        EmojiItem("\u{1F44C}", keywords: ["ok", "hand"]),
        EmojiItem("\u{1F90C}", keywords: ["pinched", "fingers"]),
        EmojiItem("\u{1F90F}", keywords: ["pinching", "hand"]),
        EmojiItem("\u{270C}\u{FE0F}", keywords: ["victory", "peace"]),
        EmojiItem("\u{1F91E}", keywords: ["crossed", "fingers", "luck"]),
        EmojiItem("\u{1FAF0}", keywords: ["hand", "with", "finger"]),
        EmojiItem("\u{1F91F}", keywords: ["love", "you", "gesture"]),
        EmojiItem("\u{1F918}", keywords: ["rock", "on", "metal"]),
        EmojiItem("\u{1F919}", keywords: ["call", "me", "hand"]),
        EmojiItem("\u{1F448}", keywords: ["point", "left"]),
        EmojiItem("\u{1F449}", keywords: ["point", "right"]),
        EmojiItem("\u{1F446}", keywords: ["point", "up"]),
        EmojiItem("\u{1F447}", keywords: ["point", "down"]),
        EmojiItem("\u{261D}\u{FE0F}", keywords: ["index", "pointing", "up"]),
        EmojiItem("\u{1FAF5}", keywords: ["point", "at", "viewer"]),
        EmojiItem("\u{1F44D}", keywords: ["thumbs", "up", "like"]),
        EmojiItem("\u{1F44E}", keywords: ["thumbs", "down", "dislike"]),
        EmojiItem("\u{270A}", keywords: ["fist", "raised"]),
        EmojiItem("\u{1F44A}", keywords: ["punch", "fist", "bump"]),
        EmojiItem("\u{1F91B}", keywords: ["left", "fist"]),
        EmojiItem("\u{1F91C}", keywords: ["right", "fist"]),
        EmojiItem("\u{1F44F}", keywords: ["clap", "applause"]),
        EmojiItem("\u{1F64C}", keywords: ["raised", "hands", "celebrate"]),
        EmojiItem("\u{1FAF6}", keywords: ["heart", "hands"]),
        EmojiItem("\u{1F450}", keywords: ["open", "hands"]),
        EmojiItem("\u{1F932}", keywords: ["palms", "up"]),
        EmojiItem("\u{1F91D}", keywords: ["handshake"]),
        EmojiItem("\u{1F64F}", keywords: ["pray", "please", "thanks"]),
        EmojiItem("\u{270D}\u{FE0F}", keywords: ["writing", "hand"]),
        EmojiItem("\u{1F485}", keywords: ["nail", "polish"]),
        EmojiItem("\u{1F933}", keywords: ["selfie"]),
        EmojiItem("\u{1F4AA}", keywords: ["muscle", "strong", "flex"]),
    ]

    static let hearts: [EmojiItem] = [
        EmojiItem("\u{2764}\u{FE0F}", keywords: ["red", "heart", "love"]),
        EmojiItem("\u{1F9E1}", keywords: ["orange", "heart"]),
        EmojiItem("\u{1F49B}", keywords: ["yellow", "heart"]),
        EmojiItem("\u{1F49A}", keywords: ["green", "heart"]),
        EmojiItem("\u{1F499}", keywords: ["blue", "heart"]),
        EmojiItem("\u{1F49C}", keywords: ["purple", "heart"]),
        EmojiItem("\u{1F90E}", keywords: ["brown", "heart"]),
        EmojiItem("\u{1F5A4}", keywords: ["black", "heart"]),
        EmojiItem("\u{1FA76}", keywords: ["light", "blue", "heart"]),
        EmojiItem("\u{1FA77}", keywords: ["pink", "heart"]),
        EmojiItem("\u{1F90D}", keywords: ["white", "heart"]),
        EmojiItem("\u{1F494}", keywords: ["broken", "heart"]),
        EmojiItem("\u{2764}\u{FE0F}\u{200D}\u{1F525}", keywords: ["heart", "on", "fire"]),
        EmojiItem("\u{2764}\u{FE0F}\u{200D}\u{1FA79}", keywords: ["mending", "heart"]),
        EmojiItem("\u{1F495}", keywords: ["two", "hearts"]),
        EmojiItem("\u{1F49E}", keywords: ["revolving", "hearts"]),
        EmojiItem("\u{1F493}", keywords: ["heartbeat"]),
        EmojiItem("\u{1F497}", keywords: ["growing", "heart"]),
        EmojiItem("\u{1F496}", keywords: ["sparkling", "heart"]),
        EmojiItem("\u{1F498}", keywords: ["cupid", "arrow", "heart"]),
        EmojiItem("\u{1F49D}", keywords: ["gift", "heart", "ribbon"]),
        EmojiItem("\u{1F49F}", keywords: ["heart", "decoration"]),
        EmojiItem("\u{2763}\u{FE0F}", keywords: ["heart", "exclamation"]),
        EmojiItem("\u{1F48B}", keywords: ["kiss", "lips"]),
        EmojiItem("\u{1F4AF}", keywords: ["hundred", "perfect", "score"]),
        EmojiItem("\u{1F4A2}", keywords: ["anger"]),
        EmojiItem("\u{1F4A5}", keywords: ["boom", "collision"]),
        EmojiItem("\u{1F4AB}", keywords: ["dizzy", "stars"]),
        EmojiItem("\u{1F4A6}", keywords: ["sweat", "droplets"]),
        EmojiItem("\u{1F4A8}", keywords: ["dash", "wind"]),
        EmojiItem("\u{1F573}\u{FE0F}", keywords: ["hole"]),
        EmojiItem("\u{1F4AC}", keywords: ["speech", "bubble"]),
        EmojiItem("\u{1F4AD}", keywords: ["thought", "bubble"]),
        EmojiItem("\u{1F4A4}", keywords: ["zzz", "sleep"]),
    ]

    static let nature: [EmojiItem] = [
        EmojiItem("\u{1F331}", keywords: ["seedling", "plant", "grow"]),
        EmojiItem("\u{1F332}", keywords: ["evergreen", "tree"]),
        EmojiItem("\u{1F333}", keywords: ["deciduous", "tree"]),
        EmojiItem("\u{1F334}", keywords: ["palm", "tree"]),
        EmojiItem("\u{1F335}", keywords: ["cactus"]),
        EmojiItem("\u{1F33E}", keywords: ["rice", "sheaf"]),
        EmojiItem("\u{1F33F}", keywords: ["herb"]),
        EmojiItem("\u{2618}\u{FE0F}", keywords: ["shamrock", "clover"]),
        EmojiItem("\u{1F340}", keywords: ["four", "leaf", "clover", "luck"]),
        EmojiItem("\u{1F341}", keywords: ["maple", "leaf", "fall"]),
        EmojiItem("\u{1F342}", keywords: ["fallen", "leaf", "autumn"]),
        EmojiItem("\u{1F343}", keywords: ["leaf", "fluttering", "wind"]),
        EmojiItem("\u{1FAB9}", keywords: ["empty", "nest"]),
        EmojiItem("\u{1FAB4}", keywords: ["potted", "plant"]),
        EmojiItem("\u{1F490}", keywords: ["bouquet", "flowers"]),
        EmojiItem("\u{1F337}", keywords: ["tulip"]),
        EmojiItem("\u{1F339}", keywords: ["rose"]),
        EmojiItem("\u{1F33A}", keywords: ["hibiscus"]),
        EmojiItem("\u{1F33B}", keywords: ["sunflower"]),
        EmojiItem("\u{1F33C}", keywords: ["blossom"]),
        EmojiItem("\u{1F338}", keywords: ["cherry", "blossom"]),
        EmojiItem("\u{1F4AE}", keywords: ["white", "flower"]),
        EmojiItem("\u{1F3F5}\u{FE0F}", keywords: ["rosette"]),
        EmojiItem("\u{1F325}\u{FE0F}", keywords: ["sun", "behind", "cloud"]),
        EmojiItem("\u{1F326}\u{FE0F}", keywords: ["sun", "rain"]),
        EmojiItem("\u{1F327}\u{FE0F}", keywords: ["rain", "cloud"]),
        EmojiItem("\u{26C8}\u{FE0F}", keywords: ["thunder", "rain"]),
        EmojiItem("\u{1F308}", keywords: ["rainbow"]),
        EmojiItem("\u{2B50}", keywords: ["star"]),
        EmojiItem("\u{1F31F}", keywords: ["glowing", "star"]),
        EmojiItem("\u{1F320}", keywords: ["shooting", "star"]),
        EmojiItem("\u{2604}\u{FE0F}", keywords: ["comet"]),
        EmojiItem("\u{2600}\u{FE0F}", keywords: ["sun"]),
        EmojiItem("\u{1F31E}", keywords: ["sun", "face"]),
        EmojiItem("\u{1F31D}", keywords: ["full", "moon", "face"]),
        EmojiItem("\u{1F319}", keywords: ["crescent", "moon"]),
        EmojiItem("\u{1F525}", keywords: ["fire", "hot"]),
        EmojiItem("\u{1F4A7}", keywords: ["droplet", "water"]),
        EmojiItem("\u{1F30A}", keywords: ["wave", "ocean"]),
    ]

    static let animals: [EmojiItem] = [
        EmojiItem("\u{1F436}", keywords: ["dog", "face"]),
        EmojiItem("\u{1F431}", keywords: ["cat", "face"]),
        EmojiItem("\u{1F42D}", keywords: ["mouse", "face"]),
        EmojiItem("\u{1F439}", keywords: ["hamster"]),
        EmojiItem("\u{1F430}", keywords: ["rabbit", "bunny"]),
        EmojiItem("\u{1F98A}", keywords: ["fox"]),
        EmojiItem("\u{1F43B}", keywords: ["bear"]),
        EmojiItem("\u{1F43C}", keywords: ["panda"]),
        EmojiItem("\u{1F428}", keywords: ["koala"]),
        EmojiItem("\u{1F42F}", keywords: ["tiger"]),
        EmojiItem("\u{1F981}", keywords: ["lion"]),
        EmojiItem("\u{1F42E}", keywords: ["cow"]),
        EmojiItem("\u{1F437}", keywords: ["pig"]),
        EmojiItem("\u{1F438}", keywords: ["frog"]),
        EmojiItem("\u{1F435}", keywords: ["monkey"]),
        EmojiItem("\u{1F648}", keywords: ["see", "no", "evil"]),
        EmojiItem("\u{1F649}", keywords: ["hear", "no", "evil"]),
        EmojiItem("\u{1F64A}", keywords: ["speak", "no", "evil"]),
        EmojiItem("\u{1F412}", keywords: ["monkey"]),
        EmojiItem("\u{1F414}", keywords: ["chicken"]),
        EmojiItem("\u{1F427}", keywords: ["penguin"]),
        EmojiItem("\u{1F426}", keywords: ["bird"]),
        EmojiItem("\u{1F985}", keywords: ["eagle"]),
        EmojiItem("\u{1F986}", keywords: ["duck"]),
        EmojiItem("\u{1F989}", keywords: ["owl"]),
        EmojiItem("\u{1F9A9}", keywords: ["flamingo"]),
        EmojiItem("\u{1F99A}", keywords: ["peacock"]),
        EmojiItem("\u{1F41B}", keywords: ["bug", "caterpillar"]),
        EmojiItem("\u{1F41C}", keywords: ["ant"]),
        EmojiItem("\u{1F41D}", keywords: ["bee", "honeybee"]),
        EmojiItem("\u{1F41E}", keywords: ["ladybug"]),
        EmojiItem("\u{1F98B}", keywords: ["butterfly"]),
        EmojiItem("\u{1F40C}", keywords: ["snail"]),
        EmojiItem("\u{1F422}", keywords: ["turtle"]),
        EmojiItem("\u{1F40D}", keywords: ["snake"]),
        EmojiItem("\u{1F982}", keywords: ["scorpion"]),
        EmojiItem("\u{1F433}", keywords: ["whale"]),
        EmojiItem("\u{1F42C}", keywords: ["dolphin"]),
        EmojiItem("\u{1F41F}", keywords: ["fish"]),
        EmojiItem("\u{1F420}", keywords: ["tropical", "fish"]),
        EmojiItem("\u{1F419}", keywords: ["octopus"]),
        EmojiItem("\u{1F41A}", keywords: ["shell"]),
        EmojiItem("\u{1F980}", keywords: ["crab"]),
        EmojiItem("\u{1F990}", keywords: ["shrimp"]),
        EmojiItem("\u{1F99E}", keywords: ["lobster"]),
        EmojiItem("\u{1F9AB}", keywords: ["beaver"]),
        EmojiItem("\u{1F999}", keywords: ["llama"]),
        EmojiItem("\u{1F984}", keywords: ["unicorn"]),
    ]

    static let food: [EmojiItem] = [
        EmojiItem("\u{1F34E}", keywords: ["red", "apple"]),
        EmojiItem("\u{1F34F}", keywords: ["green", "apple"]),
        EmojiItem("\u{1F34A}", keywords: ["tangerine", "orange"]),
        EmojiItem("\u{1F34B}", keywords: ["lemon"]),
        EmojiItem("\u{1F34C}", keywords: ["banana"]),
        EmojiItem("\u{1F349}", keywords: ["watermelon"]),
        EmojiItem("\u{1F347}", keywords: ["grapes"]),
        EmojiItem("\u{1F353}", keywords: ["strawberry"]),
        EmojiItem("\u{1FAD0}", keywords: ["blueberry"]),
        EmojiItem("\u{1F352}", keywords: ["cherry"]),
        EmojiItem("\u{1F351}", keywords: ["peach"]),
        EmojiItem("\u{1F34D}", keywords: ["pineapple"]),
        EmojiItem("\u{1F96D}", keywords: ["mango"]),
        EmojiItem("\u{1F95D}", keywords: ["kiwi"]),
        EmojiItem("\u{1F345}", keywords: ["tomato"]),
        EmojiItem("\u{1F955}", keywords: ["carrot"]),
        EmojiItem("\u{1F33D}", keywords: ["corn"]),
        EmojiItem("\u{1F336}\u{FE0F}", keywords: ["hot", "pepper"]),
        EmojiItem("\u{1F966}", keywords: ["broccoli"]),
        EmojiItem("\u{1F344}", keywords: ["mushroom"]),
        EmojiItem("\u{1F95C}", keywords: ["peanut"]),
        EmojiItem("\u{1F35E}", keywords: ["bread"]),
        EmojiItem("\u{1F950}", keywords: ["croissant"]),
        EmojiItem("\u{1F956}", keywords: ["baguette"]),
        EmojiItem("\u{1F968}", keywords: ["pretzel"]),
        EmojiItem("\u{1F9C0}", keywords: ["cheese"]),
        EmojiItem("\u{1F356}", keywords: ["meat", "bone"]),
        EmojiItem("\u{1F354}", keywords: ["hamburger", "burger"]),
        EmojiItem("\u{1F355}", keywords: ["pizza"]),
        EmojiItem("\u{1F32D}", keywords: ["hot", "dog"]),
        EmojiItem("\u{1F32E}", keywords: ["taco"]),
        EmojiItem("\u{1F32F}", keywords: ["burrito"]),
        EmojiItem("\u{1F37F}", keywords: ["popcorn"]),
        EmojiItem("\u{1F363}", keywords: ["sushi"]),
        EmojiItem("\u{1F35C}", keywords: ["ramen", "noodles"]),
        EmojiItem("\u{1F370}", keywords: ["cake", "shortcake"]),
        EmojiItem("\u{1F382}", keywords: ["birthday", "cake"]),
        EmojiItem("\u{1F36A}", keywords: ["cookie"]),
        EmojiItem("\u{1F369}", keywords: ["donut", "doughnut"]),
        EmojiItem("\u{1F36B}", keywords: ["chocolate"]),
        EmojiItem("\u{1F36C}", keywords: ["candy"]),
        EmojiItem("\u{1F36D}", keywords: ["lollipop"]),
        EmojiItem("\u{2615}", keywords: ["coffee", "hot", "beverage"]),
        EmojiItem("\u{1F375}", keywords: ["tea"]),
        EmojiItem("\u{1F37A}", keywords: ["beer"]),
        EmojiItem("\u{1F377}", keywords: ["wine"]),
        EmojiItem("\u{1F379}", keywords: ["cocktail", "tropical", "drink"]),
    ]

    static let activities: [EmojiItem] = [
        EmojiItem("\u{26BD}", keywords: ["soccer", "football"]),
        EmojiItem("\u{1F3C0}", keywords: ["basketball"]),
        EmojiItem("\u{1F3C8}", keywords: ["football", "american"]),
        EmojiItem("\u{26BE}", keywords: ["baseball"]),
        EmojiItem("\u{1F3BE}", keywords: ["tennis"]),
        EmojiItem("\u{1F3D0}", keywords: ["volleyball"]),
        EmojiItem("\u{1F3C9}", keywords: ["rugby"]),
        EmojiItem("\u{1F3B1}", keywords: ["pool", "billiards"]),
        EmojiItem("\u{1F3D3}", keywords: ["ping", "pong", "table", "tennis"]),
        EmojiItem("\u{1F3F8}", keywords: ["badminton"]),
        EmojiItem("\u{1F94A}", keywords: ["boxing", "glove"]),
        EmojiItem("\u{1F94B}", keywords: ["martial", "arts"]),
        EmojiItem("\u{26F3}", keywords: ["golf"]),
        EmojiItem("\u{1F3C4}", keywords: ["surfing"]),
        EmojiItem("\u{1F3CA}", keywords: ["swimming"]),
        EmojiItem("\u{1F6B4}", keywords: ["cycling", "biking"]),
        EmojiItem("\u{1F3CB}\u{FE0F}", keywords: ["weight", "lifting"]),
        EmojiItem("\u{1F3AE}", keywords: ["video", "game", "controller"]),
        EmojiItem("\u{1F3B2}", keywords: ["dice", "game"]),
        EmojiItem("\u{1F3AF}", keywords: ["dart", "target", "bullseye"]),
        EmojiItem("\u{1F3B3}", keywords: ["bowling"]),
        EmojiItem("\u{1F3A8}", keywords: ["art", "palette", "painting"]),
        EmojiItem("\u{1F3AD}", keywords: ["performing", "arts", "theater"]),
        EmojiItem("\u{1F3B5}", keywords: ["music", "note"]),
        EmojiItem("\u{1F3B6}", keywords: ["music", "notes"]),
        EmojiItem("\u{1F3A4}", keywords: ["microphone", "karaoke"]),
        EmojiItem("\u{1F3B8}", keywords: ["guitar"]),
        EmojiItem("\u{1F3B9}", keywords: ["piano", "keyboard"]),
        EmojiItem("\u{1F3BA}", keywords: ["trumpet"]),
        EmojiItem("\u{1F941}", keywords: ["drum"]),
        EmojiItem("\u{1F3AC}", keywords: ["movie", "clapper"]),
        EmojiItem("\u{1F3A7}", keywords: ["headphones"]),
        EmojiItem("\u{1F3AA}", keywords: ["circus", "tent"]),
        EmojiItem("\u{1FA81}", keywords: ["kite"]),
        EmojiItem("\u{1F9E9}", keywords: ["puzzle", "piece"]),
        EmojiItem("\u{1F3C6}", keywords: ["trophy"]),
        EmojiItem("\u{1F3C5}", keywords: ["medal", "sports"]),
        EmojiItem("\u{1F947}", keywords: ["gold", "medal", "first"]),
        EmojiItem("\u{1F948}", keywords: ["silver", "medal", "second"]),
        EmojiItem("\u{1F949}", keywords: ["bronze", "medal", "third"]),
    ]

    static let travel: [EmojiItem] = [
        EmojiItem("\u{1F697}", keywords: ["car", "automobile"]),
        EmojiItem("\u{1F695}", keywords: ["taxi"]),
        EmojiItem("\u{1F68C}", keywords: ["bus"]),
        EmojiItem("\u{1F693}", keywords: ["police", "car"]),
        EmojiItem("\u{1F691}", keywords: ["ambulance"]),
        EmojiItem("\u{1F692}", keywords: ["fire", "engine"]),
        EmojiItem("\u{1F6F5}", keywords: ["scooter"]),
        EmojiItem("\u{1F6B2}", keywords: ["bicycle", "bike"]),
        EmojiItem("\u{1F682}", keywords: ["locomotive", "train"]),
        EmojiItem("\u{1F685}", keywords: ["bullet", "train"]),
        EmojiItem("\u{2708}\u{FE0F}", keywords: ["airplane"]),
        EmojiItem("\u{1F680}", keywords: ["rocket"]),
        EmojiItem("\u{1F6F8}", keywords: ["flying", "saucer", "ufo"]),
        EmojiItem("\u{1F6F6}", keywords: ["canoe", "kayak"]),
        EmojiItem("\u{1F6A2}", keywords: ["ship"]),
        EmojiItem("\u{26F5}", keywords: ["sailboat"]),
        EmojiItem("\u{1F3E0}", keywords: ["house", "home"]),
        EmojiItem("\u{1F3E2}", keywords: ["office", "building"]),
        EmojiItem("\u{1F3EB}", keywords: ["school"]),
        EmojiItem("\u{1F3E5}", keywords: ["hospital"]),
        EmojiItem("\u{1F3EA}", keywords: ["store", "shop"]),
        EmojiItem("\u{1F3E8}", keywords: ["hotel"]),
        EmojiItem("\u{1F3F0}", keywords: ["castle"]),
        EmojiItem("\u{26EA}", keywords: ["church"]),
        EmojiItem("\u{1F5FC}", keywords: ["tokyo", "tower"]),
        EmojiItem("\u{1F5FD}", keywords: ["statue", "liberty"]),
        EmojiItem("\u{1F5FB}", keywords: ["mount", "fuji"]),
        EmojiItem("\u{1F30D}", keywords: ["globe", "earth"]),
        EmojiItem("\u{1F30E}", keywords: ["globe", "americas"]),
        EmojiItem("\u{1F30F}", keywords: ["globe", "asia"]),
        EmojiItem("\u{1F3D6}\u{FE0F}", keywords: ["beach", "umbrella"]),
        EmojiItem("\u{1F3D4}\u{FE0F}", keywords: ["mountain", "snow"]),
        EmojiItem("\u{26F0}\u{FE0F}", keywords: ["mountain"]),
        EmojiItem("\u{1F3DD}\u{FE0F}", keywords: ["desert", "island"]),
        EmojiItem("\u{1F9ED}", keywords: ["compass"]),
        EmojiItem("\u{26FA}", keywords: ["tent", "camping"]),
    ]

    static let objects: [EmojiItem] = [
        EmojiItem("\u{1F4A1}", keywords: ["light", "bulb", "idea"]),
        EmojiItem("\u{1F526}", keywords: ["flashlight"]),
        EmojiItem("\u{1F56F}\u{FE0F}", keywords: ["candle"]),
        EmojiItem("\u{1F4D6}", keywords: ["open", "book"]),
        EmojiItem("\u{1F4D5}", keywords: ["closed", "book"]),
        EmojiItem("\u{1F4DA}", keywords: ["books"]),
        EmojiItem("\u{1F4D3}", keywords: ["notebook"]),
        EmojiItem("\u{1F4D2}", keywords: ["ledger"]),
        EmojiItem("\u{1F4DD}", keywords: ["memo", "note", "writing"]),
        EmojiItem("\u{1F4C4}", keywords: ["page", "facing", "up"]),
        EmojiItem("\u{1F4CB}", keywords: ["clipboard"]),
        EmojiItem("\u{1F4CC}", keywords: ["pushpin"]),
        EmojiItem("\u{1F4CE}", keywords: ["paperclip"]),
        EmojiItem("\u{2702}\u{FE0F}", keywords: ["scissors"]),
        EmojiItem("\u{1F4CF}", keywords: ["ruler"]),
        EmojiItem("\u{1F4D0}", keywords: ["triangular", "ruler"]),
        EmojiItem("\u{1F5C2}\u{FE0F}", keywords: ["dividers", "binder"]),
        EmojiItem("\u{1F4C1}", keywords: ["folder"]),
        EmojiItem("\u{1F4C2}", keywords: ["open", "folder"]),
        EmojiItem("\u{1F5C3}\u{FE0F}", keywords: ["card", "file", "box"]),
        EmojiItem("\u{1F4C5}", keywords: ["calendar"]),
        EmojiItem("\u{1F5D3}\u{FE0F}", keywords: ["spiral", "calendar"]),
        EmojiItem("\u{1F4CA}", keywords: ["chart", "bar"]),
        EmojiItem("\u{1F4C8}", keywords: ["chart", "increasing"]),
        EmojiItem("\u{1F4C9}", keywords: ["chart", "decreasing"]),
        EmojiItem("\u{1F4E7}", keywords: ["email", "mail"]),
        EmojiItem("\u{1F4E8}", keywords: ["incoming", "envelope"]),
        EmojiItem("\u{1F517}", keywords: ["link"]),
        EmojiItem("\u{1F527}", keywords: ["wrench", "tool"]),
        EmojiItem("\u{1F528}", keywords: ["hammer"]),
        EmojiItem("\u{1F529}", keywords: ["nut", "bolt"]),
        EmojiItem("\u{2699}\u{FE0F}", keywords: ["gear", "settings"]),
        EmojiItem("\u{1F50D}", keywords: ["magnifying", "glass", "search"]),
        EmojiItem("\u{1F50E}", keywords: ["magnifying", "glass", "right"]),
        EmojiItem("\u{1F512}", keywords: ["lock", "locked"]),
        EmojiItem("\u{1F513}", keywords: ["unlock", "unlocked"]),
        EmojiItem("\u{1F511}", keywords: ["key"]),
        EmojiItem("\u{1F4BB}", keywords: ["laptop", "computer"]),
        EmojiItem("\u{1F5A5}\u{FE0F}", keywords: ["desktop", "computer"]),
        EmojiItem("\u{1F4F1}", keywords: ["phone", "mobile"]),
        EmojiItem("\u{1F48E}", keywords: ["gem", "diamond"]),
        EmojiItem("\u{1F6E1}\u{FE0F}", keywords: ["shield"]),
        EmojiItem("\u{1F514}", keywords: ["bell"]),
        EmojiItem("\u{1F3F7}\u{FE0F}", keywords: ["label", "tag"]),
    ]

    static let symbols: [EmojiItem] = [
        EmojiItem("\u{2705}", keywords: ["check", "mark", "done"]),
        EmojiItem("\u{274C}", keywords: ["cross", "mark", "no"]),
        EmojiItem("\u{274E}", keywords: ["cross", "mark", "square"]),
        EmojiItem("\u{2757}", keywords: ["exclamation", "mark"]),
        EmojiItem("\u{2753}", keywords: ["question", "mark"]),
        EmojiItem("\u{26A0}\u{FE0F}", keywords: ["warning"]),
        EmojiItem("\u{1F6AB}", keywords: ["prohibited", "no"]),
        EmojiItem("\u{267B}\u{FE0F}", keywords: ["recycle"]),
        EmojiItem("\u{2728}", keywords: ["sparkles"]),
        EmojiItem("\u{1F4A0}", keywords: ["diamond", "dot"]),
        EmojiItem("\u{1F300}", keywords: ["cyclone", "spiral"]),
        EmojiItem("\u{267E}\u{FE0F}", keywords: ["infinity"]),
        EmojiItem("\u{1F504}", keywords: ["arrows", "counterclockwise"]),
        EmojiItem("\u{1F503}", keywords: ["arrows", "clockwise"]),
        EmojiItem("\u{1F519}", keywords: ["back", "arrow"]),
        EmojiItem("\u{1F51A}", keywords: ["end", "arrow"]),
        EmojiItem("\u{1F51B}", keywords: ["on", "arrow"]),
        EmojiItem("\u{1F51C}", keywords: ["soon", "arrow"]),
        EmojiItem("\u{1F51D}", keywords: ["top", "arrow"]),
        EmojiItem("\u{25B6}\u{FE0F}", keywords: ["play", "button"]),
        EmojiItem("\u{23F8}\u{FE0F}", keywords: ["pause"]),
        EmojiItem("\u{23F9}\u{FE0F}", keywords: ["stop"]),
        EmojiItem("\u{23FA}\u{FE0F}", keywords: ["record"]),
        EmojiItem("\u{2795}", keywords: ["plus", "add"]),
        EmojiItem("\u{2796}", keywords: ["minus", "subtract"]),
        EmojiItem("\u{2716}\u{FE0F}", keywords: ["multiply"]),
        EmojiItem("\u{2797}", keywords: ["divide"]),
        EmojiItem("\u{1F7F0}", keywords: ["equals"]),
        EmojiItem("\u{1F4B2}", keywords: ["dollar"]),
        EmojiItem("\u{1F4B0}", keywords: ["money", "bag"]),
        EmojiItem("\u{2696}\u{FE0F}", keywords: ["balance", "scales"]),
        EmojiItem("\u{1F6A9}", keywords: ["triangular", "flag"]),
        EmojiItem("\u{2B50}", keywords: ["star"]),
        EmojiItem("\u{26A1}", keywords: ["lightning", "zap"]),
        EmojiItem("\u{1F3AF}", keywords: ["target", "bullseye"]),
    ]

    static let flags: [EmojiItem] = [
        EmojiItem("\u{1F3F3}\u{FE0F}", keywords: ["white", "flag"]),
        EmojiItem("\u{1F3F4}", keywords: ["black", "flag"]),
        EmojiItem("\u{1F3C1}", keywords: ["checkered", "flag"]),
        EmojiItem("\u{1F6A9}", keywords: ["triangular", "flag"]),
        EmojiItem("\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}", keywords: ["rainbow", "flag", "pride"]),
        EmojiItem("\u{1F1FA}\u{1F1F8}", keywords: ["us", "usa", "united", "states"]),
        EmojiItem("\u{1F1EC}\u{1F1E7}", keywords: ["gb", "uk", "britain"]),
        EmojiItem("\u{1F1E8}\u{1F1E6}", keywords: ["canada"]),
        EmojiItem("\u{1F1E6}\u{1F1FA}", keywords: ["australia"]),
        EmojiItem("\u{1F1E9}\u{1F1EA}", keywords: ["germany"]),
        EmojiItem("\u{1F1EB}\u{1F1F7}", keywords: ["france"]),
        EmojiItem("\u{1F1EA}\u{1F1F8}", keywords: ["spain"]),
        EmojiItem("\u{1F1EE}\u{1F1F9}", keywords: ["italy"]),
        EmojiItem("\u{1F1EF}\u{1F1F5}", keywords: ["japan"]),
        EmojiItem("\u{1F1F0}\u{1F1F7}", keywords: ["korea", "south"]),
        EmojiItem("\u{1F1E8}\u{1F1F3}", keywords: ["china"]),
        EmojiItem("\u{1F1EE}\u{1F1F3}", keywords: ["india"]),
        EmojiItem("\u{1F1E7}\u{1F1F7}", keywords: ["brazil"]),
        EmojiItem("\u{1F1F2}\u{1F1FD}", keywords: ["mexico"]),
        EmojiItem("\u{1F1F7}\u{1F1FA}", keywords: ["russia"]),
    ]

    static var allEmojis: [EmojiItem] {
        var seen = Set<String>()
        return categories
            .flatMap { $0.1 }
            .filter { seen.insert($0.emoji).inserted }
    }

    static var allEmojiCharacters: [String] {
        uniqueEmojis(allEmojis.map(\.emoji) + EmojiUnicodeGenerator.generated)
    }

    static var searchableEmojis: [EmojiItem] {
        var indexed: [String: EmojiItem] = [:]
        for item in allEmojis where indexed[item.emoji] == nil {
            indexed[item.emoji] = item
        }
        for emoji in allEmojiCharacters where indexed[emoji] == nil {
            indexed[emoji] = EmojiItem(emoji, keywords: derivedKeywords(for: emoji))
        }
        return indexed.values.sorted { $0.emoji < $1.emoji }
    }

    private static func uniqueEmojis(_ source: [String]) -> [String] {
        var seen = Set<String>()
        return source.filter { seen.insert($0).inserted }
    }

    private static func derivedKeywords(for emoji: String) -> [String] {
        let tokens = emoji.unicodeScalars
            .compactMap { $0.properties.name?.lowercased() }
            .flatMap { name in
                name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
            }
        var seen = Set<String>()
        return tokens.filter { seen.insert($0).inserted }
    }
}

private enum EmojiUnicodeGenerator {
    private static let sourceRanges: [ClosedRange<Int>] = [
        0x00A9...0x00AE,
        0x203C...0x3299,
        0x1F000...0x1FAFF,
    ]

    private static let skinToneRange = 0x1F3FB...0x1F3FF
    private static let regionalIndicatorRange = 0x1F1E6...0x1F1FF
    private static let disallowedScalars: Set<UInt32> = [0x200D, 0x20E3, 0xFE0E, 0xFE0F]

    static let generated: [String] = {
        var result: [String] = []
        var seen = Set<String>()

        func append(_ emoji: String) {
            guard seen.insert(emoji).inserted else { return }
            result.append(emoji)
        }

        for range in sourceRanges {
            for value in range {
                guard let scalar = UnicodeScalar(value) else { continue }
                if isSupportedStandaloneEmoji(scalar) {
                    append(String(scalar))
                }
            }
        }

        for first in regionalIndicatorRange {
            guard let left = UnicodeScalar(first) else { continue }
            for second in regionalIndicatorRange {
                guard let right = UnicodeScalar(second) else { continue }
                append(String(left) + String(right))
            }
        }

        let keycapBases = ["#", "*", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        for base in keycapBases {
            append(base + "\u{FE0F}\u{20E3}")
        }

        return result
    }()

    private static func isSupportedStandaloneEmoji(_ scalar: UnicodeScalar) -> Bool {
        let value = Int(scalar.value)
        if disallowedScalars.contains(scalar.value) { return false }
        if skinToneRange.contains(value) { return false }
        if regionalIndicatorRange.contains(value) { return false }
        if value == 0x0023 || value == 0x002A || (0x0030...0x0039).contains(value) { return false }
        return scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
    }
}

// MARK: - Recent Emojis Manager

class RecentEmojisManager {
    static let shared = RecentEmojisManager()
    private let key = "recentEmojis"
    private let maxRecent = 8

    func getRecent() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func addRecent(_ emoji: String) {
        var recent = getRecent()
        recent.removeAll { $0 == emoji }
        recent.insert(emoji, at: 0)
        if recent.count > maxRecent {
            recent = Array(recent.prefix(maxRecent))
        }
        UserDefaults.standard.set(recent, forKey: key)
    }
}

// MARK: - Emoji Picker Tab

enum EmojiPickerTab: String, CaseIterable {
    case emoji = "Emoji"
    case icons = "Icons"
    case upload = "Upload"
}

// MARK: - Full Emoji Picker View

struct FullEmojiPickerView: View {
    @Binding var selectedEmoji: String?
    var onCustomIconSelected: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedTab: EmojiPickerTab = .emoji
    @State private var selectedCategory: EmojiCategory = .smileys
    @State private var recentEmojis: [String] = []

    private let emojiGridColumns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8)

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(EmojiPickerTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            switch selectedTab {
            case .emoji:
                emojiTabContent
            case .icons:
                sfSymbolsContent
            case .upload:
                uploadContent
            }

            Divider()

            // Bottom bar: Random + Remove
            HStack {
                Button(action: selectRandomEmoji) {
                    HStack(spacing: 4) {
                        Image(systemName: "shuffle")
                        Text("Random")
                    }
                    .font(.system(size: 13))
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Remove") {
                    selectedEmoji = nil
                    dismiss()
                }
                .font(.system(size: 13))
                .foregroundColor(.red)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(width: 420, height: 520)
        .onAppear {
            recentEmojis = RecentEmojisManager.shared.getRecent()
        }
    }

    // MARK: - Emoji Tab

    private var emojiTabContent: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search emoji...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.fallbackBgSecondary)
            .cornerRadius(6)
            .padding(.horizontal, 18)
            .padding(.top, 12)

            if searchText.isEmpty {
                // Category bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(EmojiCategory.allCases) { category in
                            if category == .recent && recentEmojis.isEmpty { EmptyView() } else {
                                Button(action: { selectedCategory = category }) {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 14))
                                        .foregroundColor(selectedCategory == category ? .accentColor : .secondary)
                                        .frame(width: 26, height: 26)
                                        .background(selectedCategory == category ? Color.accentColor.opacity(0.15) : Color.clear)
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .help(category.rawValue)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Emoji grid
                ScrollView {
                    emojiGrid(for: selectedCategory)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                }
            } else {
                // Search results
                ScrollView {
                    let results = searchResults
                    if results.isEmpty {
                        Text("No emoji found")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .padding(.top, 40)
                    } else {
                        emojiGridItems(results)
                            .padding(.horizontal, 18)
                            .padding(.top, 8)
                            .padding(.bottom, 10)
                    }
                }
            }
        }
    }

    private func emojiGrid(for category: EmojiCategory) -> some View {
        Group {
            if category == .recent {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                    emojiGridItems(recentEmojis)
                }
            } else if category == .all {
                VStack(alignment: .leading, spacing: 4) {
                    Text("All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                    emojiGridItems(EmojiData.allEmojiCharacters)
                }
            } else {
                let items = EmojiData.categories.first(where: { $0.0 == category })?.1 ?? []
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                    emojiGridItems(items.map(\.emoji))
                }
            }
        }
    }

    private func emojiGridItems(_ emojis: [String]) -> some View {
        let uniqueEmojis = deduplicated(emojis)
        return LazyVGrid(columns: emojiGridColumns, spacing: 6) {
            ForEach(uniqueEmojis, id: \.self) { emoji in
                Button(action: { selectEmoji(emoji) }) {
                    Text(emoji)
                        .font(.system(size: 24))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .background(selectedEmoji == emoji ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchResults: [String] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else { return [] }
        return EmojiData.searchableEmojis.compactMap { item in
            if item.emoji == query || item.keywords.contains(where: { $0.contains(query) }) {
                return item.emoji
            }
            return nil
        }
    }

    // MARK: - SF Symbols Tab

    private var sfSymbolsContent: some View {
        let symbolNames = [
            "doc.text", "folder", "tray", "archivebox", "book", "bookmark",
            "pencil", "square.and.pencil", "highlighter", "note.text",
            "list.bullet", "list.number", "checklist", "chart.bar",
            "star", "heart", "flag", "tag", "bell", "pin",
            "link", "paperclip", "globe", "lock", "key",
            "gear", "wrench.and.screwdriver", "hammer", "ant",
            "lightbulb", "bolt", "flame", "drop", "leaf",
            "person", "person.2", "figure.walk", "brain",
            "desktopcomputer", "laptopcomputer", "iphone", "gamecontroller",
            "music.note", "camera", "photo", "film",
            "envelope", "phone", "message", "bubble.left",
            "cart", "creditcard", "dollarsign.circle",
            "house", "building.2", "map", "location",
            "clock", "calendar", "alarm", "timer",
            "shield", "checkmark.seal", "xmark.seal",
            "exclamationmark.triangle", "info.circle", "questionmark.circle",
        ]

        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8), spacing: 4) {
                ForEach(symbolNames, id: \.self) { name in
                    Button(action: {
                        // Store SF Symbol as special format
                        selectedEmoji = "sf:\(name)"
                        dismiss()
                    }) {
                        Image(systemName: name)
                            .font(.system(size: 17))
                            .frame(width: 36, height: 36)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .background(Color.fallbackSurfaceSubtle)
                    .cornerRadius(4)
                    .help(name)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Upload Tab

    private var uploadContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("Upload a custom icon")
                .font(.system(size: 15))
                .foregroundColor(.secondary)

            Text("PNG, JPG, GIF, or WebP. Max 2MB.")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))

            Button("Choose File") {
                chooseCustomIcon()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func selectEmoji(_ emoji: String) {
        selectedEmoji = emoji
        RecentEmojisManager.shared.addRecent(emoji)
        recentEmojis = RecentEmojisManager.shared.getRecent()
        dismiss()
    }

    private func selectRandomEmoji() {
        if let random = EmojiData.allEmojiCharacters.randomElement() {
            selectEmoji(random)
        }
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func chooseCustomIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Icon Image"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Check file size (2MB max)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size <= 2 * 1024 * 1024 else {
            return
        }

        // Copy to app support directory
        if let savedPath = FileSystemService.saveIcon(from: url) {
            onCustomIconSelected?(savedPath)
            dismiss()
        }
    }
}
