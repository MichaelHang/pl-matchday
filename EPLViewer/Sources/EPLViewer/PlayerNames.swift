import Foundation

// MARK: - 球员中英文映射（数据集驱动：FPL bootstrap 骨架 + 中文覆盖层）

/// 中文球员名映射表。
///
/// 数据来源：
/// - 骨架：FPL 官方 `bootstrap-static`（公开、无需鉴权，App 运行期本来就在下）
///   提供权威且稳定的 `element id`、`web_name`、所属队——本赛季现役球员全集。
/// - 覆盖层：下方 `zhById` / `zhByName` 是人工维护的中文全名。
///
/// 匹配优先级：`id`（稳定、唯一、跨赛季/转会不随姓名变化）→ `web_name`（二级回退）
/// → 英文原名（最终回退，绝不空白）。`web_name` 可能重姓碰撞，故 `id` 为主键。
///
/// 维护：运行期 `missing(ids:)` 拿已在下的 bootstrap 球员 id 与 `zhById` 差分，
/// 即可得「本窗口/本赛季还没中文名」的现役名单；补表是机械活。
enum PlayerNameMap {
    /// FPL element id → 中文全名（主键，由 bootstrap 反查得到，跨赛季稳定）
    private static let zhById: [Int: String] = [
        1: "戴维·拉亚",   // Raya
        2: "凯帕",   // Arrizabalaga
        3: "梅斯里耶",   // Meslier
        4: "加布里埃尔·多斯·桑托斯",   // Gabriel
        5: "廷贝尔",   // J.Timber
        6: "威廉·萨利巴",   // Saliba
        7: "迈尔斯·刘易斯-斯凯利",   // Lewis-Skelly
        8: "里卡多·卡拉菲奥里",   // Calafiori
        9: "因卡皮耶",   // Hincapie
        10: "本·怀特",   // White
        11: "德雷·莫斯克拉",   // Mosquera
        12: "布卡约·萨卡",   // Saka
        13: "德克兰·赖斯",   // Rice
        14: "埃贝雷奇·埃泽",   // Eze
        15: "厄德高",   // Ødegaard
        16: "诺尼·马杜埃凯",   // Madueke
        17: "米克尔·梅里诺",   // Merino
        18: "加布里埃尔·马丁内利",   // Martinelli
        19: "马丁·祖比门迪",   // Zubimendi
        20: "马克斯·道曼",   // Dowman
        21: "诺尔加阿尔德",   // Nørgaard
        22: "伊桑·恩瓦内里",   // Nwaneri
        23: "法比奥·维埃拉",   // Fábio Vieira
        24: "赖斯·纳尔逊",   // Nelson
        25: "维克托·哲凯赖什",   // Gyökeres
        26: "凯·哈弗茨",   // Havertz
        27: "加布里埃尔·热苏斯",   // G.Jesus
        28: "埃米利亚诺·马丁内斯",   // Martinez
        29: "比佐特",   // M.Bizot
        30: "卢卡斯·迪涅",   // Digne
        31: "埃兹里·孔萨",   // Konsa
        32: "梅米·卡什",   // Cash
        33: "泰隆·明斯",   // Mings
        34: "保·托雷斯",   // Pau
        35: "博加德",   // Bogarde
        36: "伊恩·马特森",   // Maatsen
        37: "林德洛夫",   // Lindelöf
        38: "安德烈斯·加西亚",   // A.García
        39: "内德利科维奇",   // Nedeljkovic
        40: "摩根·罗杰斯",   // Rogers
        41: "布恩迪亚",   // Buendía
        42: "盖桑",   // Guessand
        43: "尤里·蒂勒曼斯",   // Tielemans
        44: "莱昂·贝利",   // Bailey
        45: "约翰·麦金",   // McGinn
        46: "罗斯·巴克利",   // Barkley
        47: "布巴卡尔·卡马拉",   // Kamara
        48: "奥纳纳",   // Onana
        49: "塞缪尔·伊林",   // Iling Jr
        50: "伯罗斯",   // Burrowes
        51: "乔治·海明斯",   // George Hemmings
        52: "埃德瓦尔德",   // Alysson
        53: "约翰·曼赞比",   // Manzambi
        54: "若昂·戈麦斯",   // Gomes
        55: "奥利·沃特金斯",   // Watkins
        56: "阿布拉哈姆",   // Abraham
        57: "彼得罗维奇",   // Petrović
        58: "福尔斯特尔",   // Forster
        59: "德恩尼斯",   // Dennis
        60: "希尔",   // Hill
        61: "特鲁弗费尔特",   // Truffert
        62: "迪阿基特",   // Diakité
        63: "米洛萨夫列维奇",   // Milosavljević
        64: "亚当·史密斯",   // Smith
        65: "阿劳霍",   // J.Araujo
        66: "索莱尔",   // Soler
        67: "拉亚恩",   // Rayan
        68: "塔维尼尔",   // Tavernier
        69: "斯科特特",   // Scott
        70: "贾斯汀·克鲁伊维特",   // Kluivert
        71: "刘易斯·库克",   // Cook
        72: "多阿克",   // Gannon-Doak
        73: "亚当斯",   // Adams
        74: "布罗奥克斯",   // Brooks
        75: "瑞安·克里斯蒂",   // Christie
        76: "托特",   // Tóth.A
        77: "阿德利",   // Adli
        78: "克罗乌皮",   // Kroupi.Jr
        79: "达尼洛·埃瓦尼松",   // Evanilson
        80: "乌纳尔",   // Enes Ünal
        81: "罗德里格斯",   // Rodríguez
        82: "凯尔莱赫尔",   // Kelleher
        83: "瓦尔迪马尔松",   // Valdimarsson
        84: "科尔利恩斯",   // Collins
        85: "塞普·范登贝尔赫",   // Van den Berg
        86: "刘易斯-波特",   // Lewis-Potter
        87: "阿耶尔",   // Ajer
        88: "卡约德",   // Kayode
        89: "里科·亨利",   // Henry
        90: "希克艾",   // Hickey
        91: "伊桑·平诺克",   // Pinnock
        92: "金志树",   // Ji-soo
        93: "施乌斯特尔",   // Schuster
        94: "沙德",   // Schade
        95: "丹戈",   // O.Dango
        96: "达姆斯高",   // Damsgaard
        97: "马蒂亚斯·延斯滕",   // Jensen
        98: "亚内尔特",   // Janelt
        99: "米兰博",   // Milambo
        100: "卡瓦略",   // Carvalho
        101: "赫恩德尔松",   // Henderson
        102: "亚尔莫尔尤克",   // Yarmoliuk
        103: "达西尔瓦",   // Dasilva
        104: "奥恩耶卡",   // Onyeka
        105: "安东尼",   // Anthony
        106: "蒂亚戈",   // Thiago
        107: "富罗",   // Furo
        108: "威尔逊",   // Wilson
        109: "巴特·费布鲁亨",   // Verbruggen
        110: "鲁什沃尔特",   // Rushworth
        111: "斯特埃莱",   // Steele
        112: "扬·范赫克",   // Van Hecke
        113: "卡迪奥格卢",   // F.Kadıoğlu
        114: "博斯卡格利",   // Boscagli
        115: "马克西姆·德屈佩",   // De Cuyper
        116: "刘易斯·邓克",   // Dunk
        117: "科波拉",   // Coppola
        118: "伊戈尔",   // Igor
        119: "科斯蒂恩哈",   // Costinha
        120: "斯沃博达",   // Svoboda
        121: "三笘薫",   // Mitoma
        122: "米恩特赫",   // Minteh
        123: "兰克·辛谢尔伍德",   // Hinshelwood
        124: "格罗斯",   // Groß
        125: "鲁特",   // Georginio
        126: "奥里莱伊",   // O'Riley
        127: "戈梅兹",   // Gomez
        128: "法昆多·博纳诺特",   // Buonanotte
        129: "扬库·阿亚里",   // Ayari
        130: "维埃弗费尔",   // Wieffer
        131: "卡洛斯·巴莱巴",   // Baleba
        132: "豪厄尔",   // Howell
        133: "沃森",   // Watson
        134: "奥里奥拉",   // Oriola
        135: "约哈恩纳",   // Yohanna
        136: "韦尔贝克",   // Welbeck
        137: "斯蒂法诺斯·齐马斯",   // Tzimas
        138: "科斯托乌拉斯",   // Kostoulas
        139: "埃文·弗格森",   // Ferguson
        140: "罗伯特·桑切斯",   // Sánchez
        141: "约根森",   // Jörgensen
        142: "亚梅斯",   // James
        143: "特雷沃·查洛巴",   // Chalobah
        144: "马洛·古斯托",   // Gusto
        145: "福法纳",   // Fofana
        146: "巴迪亚西勒",   // B.Badiashile
        147: "阿达拉比奥伊奥",   // Tosin
        148: "哈托",   // Hato
        149: "利维·科尔威尔",   // Colwill
        150: "萨尔",   // M.Sarr
        151: "阿赫埃阿姆波恩格",   // Acheampong
        152: "帕莱斯特拉",   // Palestra
        153: "阿克塞尔·迪萨西",   // Disasi
        154: "帕尔默",   // Palmer
        155: "恩佐·费尔南德斯",   // Enzo
        156: "佩德罗·内托",   // Neto
        157: "埃斯特旺·威廉",   // Estêvão
        158: "吉滕斯",   // Gittens
        159: "莫伊塞斯·凯塞多",   // Caicedo
        160: "亚历杭德罗·加纳乔",   // Garnacho
        161: "拉维阿",   // Lavia
        162: "安德烈·桑托斯",   // Andrey Santos
        163: "埃苏戈",   // D.Essugo
        164: "库埃恩达",   // Quenda
        165: "若昂·佩德罗",   // João Pedro
        166: "尼古拉·杰克逊",   // N.Jackson
        167: "利亚姆·德拉普",   // Delap
        168: "马克·吉乌",   // Marc Guiu
        169: "姆赫卡",   // Mheuka
        170: "埃梅格阿",   // Emegha
        171: "奥利弗·道文",   // Dovin
        172: "本·威尔逊",   // Wilson
        173: "特奥马斯",   // Thomas
        174: "基特赫伊恩格",   // Kitching
        175: "埃维杰克",   // van Ewijk
        176: "达西尔瓦",   // Dasilva
        177: "凯斯莱尔·哈伊德恩",   // Kesler-Hayden
        178: "比德韦尔",   // Bidwell
        179: "拉蒂贝奥迪埃雷",   // Latibeaudiere
        180: "沃奥尔费恩德恩",   // Woolfenden
        181: "米格尔·安赫尔·布劳",   // Brau
        182: "阿梅恩达",   // Amenda
        183: "鲁多尼",   // Rudoni
        184: "格里梅斯",   // Grimes
        185: "萨卡莫托",   // Sakamoto
        186: "马松·克拉尔克",   // Mason-Clark
        187: "埃克克莱斯",   // Eccles
        188: "托尔普",   // Torp
        189: "谢泼德",   // Shepherd
        190: "特赫阿乌纳",   // Tchaouna
        191: "拉斐尔·罗德里格斯",   // Borges Rodrigues
        192: "凯·安德鲁斯",   // Andrews
        193: "哈吉·赖特",   // Wright
        194: "托马斯-阿桑特",   // Thomas-Asante
        195: "西姆姆斯",   // Simms
        196: "马克洛",   // Markelo
        197: "诺曼·巴塞特",   // Bassette
        198: "赫恩德尔松",   // Henderson
        199: "贝尼特兹",   // Benitez
        200: "拉格朗日",   // Lacroix
        201: "穆诺兹",   // Muñoz
        202: "理查兹",   // Richards
        203: "卡恩沃特",   // Canvot
        204: "泰里克·米切尔",   // Mitchell
        205: "索萨",   // Sosa
        206: "里阿德",   // Chadi Riad
        207: "米恩古埃扎",   // Mingueza
        208: "马姆杜·萨尔",   // Sarr
        209: "约翰逊",   // Johnson
        210: "亚当·沃顿",   // Wharton
        211: "耶雷米·皮诺",   // Yeremy
        212: "胡格埃斯",   // Hughes
        213: "莱尔马",   // Lerma
        214: "镰田大地",   // Kamada
        215: "德文尼",   // Devenny
        216: "埃塞",   // Esse
        217: "马修斯·弗兰萨",   // M.França
        218: "阿卜杜拉耶·杜库雷",   // Doucouré
        219: "拉克-萨基",   // J.Rak-Sakyi
        220: "里奥·卡迪内斯",   // Cardines
        221: "德拉凯斯·特奥马斯",   // Drakes-Thomas
        222: "斯特兰德·拉森",   // Strand Larsen
        223: "让-菲利普·马特塔",   // Mateta
        224: "恩凯蒂亚",   // Nketiah
        225: "乌切",   // Uche
        226: "乔丹·皮克福德",   // Pickford
        227: "特拉弗斯",   // Travers
        228: "基恩格",   // King
        229: "詹姆斯·塔科夫斯基",   // Tarkowski
        230: "贾拉德·布兰斯韦特",   // Branthwaite
        231: "基恩",   // Keane
        232: "奥布莱恩",   // O'Brien
        233: "亚历克斯·墨菲",   // Mykolenko
        234: "帕特特尔松",   // Patterson
        235: "阿兹努",   // Aznou
        236: "德瓦斯布尔伊·哈尔",   // Dewsbury-Hall
        237: "恩迪亚耶",   // Ndiaye
        238: "杰克·格里利什",   // Grealish
        239: "詹姆斯·加纳",   // Garner
        240: "伊罗埃格布纳姆",   // Iroegbunam
        241: "德怀特·麦克尼尔",   // McNeil
        242: "泰里克·乔治",   // George
        243: "阿尔卡拉斯",   // Alcaraz
        244: "阿尔姆斯特罗恩格",   // Armstrong
        245: "迪布林",   // Dibling
        246: "罗尔",   // Röhl
        247: "哈克内伊",   // Hackney
        248: "贝托",   // Beto
        249: "巴里",   // Barry
        250: "贝恩德·莱诺",   // Leno
        251: "莱科姆特",   // Lecomte
        252: "麦克纳利",   // McNally
        253: "约阿希姆·安德森",   // Andersen
        254: "安东尼·罗宾逊",   // Robinson
        255: "库埃恩卡",   // J.Cuenca
        256: "肯尼·特特",   // Tete
        257: "巴塞",   // Bassey
        258: "卡斯塔涅",   // Castagne
        259: "迪奥普",   // Diop
        260: "威尔逊",   // Wilson
        261: "伊沃比",   // Iwobi
        262: "罗韦",   // Smith Rowe
        263: "凯文",   // Kevin
        264: "奥斯卡·鲍勃",   // Bobb
        265: "贝尔赫",   // Berge
        266: "卡尔尼",   // Cairney
        267: "卢基克",   // Lukić
        268: "基恩格",   // King
        269: "塞塞尼翁",   // Sessegnon
        270: "雷埃德",   // Reed
        271: "穆尼兹",   // Muniz
        272: "库西·阿萨雷",   // Kusi-Asare
        273: "弗伊尔利普斯",   // Phillips
        274: "布特拉恩德",   // Butland
        275: "哈维·卡特赖特",   // Cartwright
        276: "蒂莫西·洛-图塔拉",   // Lo-Tutala
        277: "埃加恩",   // Egan
        278: "胡格埃斯",   // Hughes
        279: "阿亚伊",   // Ajayi
        280: "科伊莱",   // Coyle
        281: "德拉梅赫",   // Drameh
        282: "吉莱斯",   // Giles
        283: "马蒂·雅各布",   // Jacob
        284: "麦卡锡",   // McCarthy
        285: "姆克纳伊尔",   // McNair
        286: "贝尔洛乌米",   // Belloumi
        287: "利亚姆·米勒",   // Millar
        288: "多韦尔",   // Dowell
        289: "克罗奥克斯",   // Crooks
        290: "斯拉特尔",   // Slater
        291: "马塔佐",   // Matazo
        292: "厄穆尔",   // Ömür
        293: "卡马拉",   // Kamara
        294: "奥斯卡·桑布拉诺",   // Zambrano
        295: "姆克布尔尼埃",   // McBurnie
        296: "阿金托拉",   // Akintola
        297: "格亚比",   // Gyabi
        298: "德斯坦",   // Destan
        299: "梅森·伯斯托",   // Burstow
        300: "瓦尔托恩",   // Walton
        301: "帕尔默",   // Palmer
        302: "布特托恩",   // Button
        303: "基普雷",   // Kipré
        304: "奥什埃阿",   // O'Shea
        305: "达维斯",   // Davis
        306: "格雷阿韦斯",   // Greaves
        307: "约翰逊",   // Johnson
        308: "富尔洛恩格",   // Furlong
        309: "达尔文·努涅斯",   // Núñez
        310: "马图西瓦",   // Matusiwa
        311: "伯恩斯",   // Burns
        312: "塔伊洛尔",   // Taylor
        313: "克拉尔凯",   // Clarke
        314: "奥格贝内",   // Ogbene
        315: "法塔乌",   // Fatawu
        316: "埃梅尔索恩恩",   // Emersonn
        317: "埃格利",   // Hirst
        318: "弗伊洛格内",   // Philogene
        319: "什莫迪奇",   // Szmodics
        320: "阿克波姆",   // Akpom
        321: "埃格利",   // Walle Egeli
        322: "阿尔-哈马迪",   // Al-Hamadi
        323: "姆卡特埃尔",   // McAteer
        324: "梅赫梅蒂",   // Mehmeti
        325: "达洛",   // Darlow
        326: "佩尔里",   // Perri
        327: "比约尔",   // Bijol
        328: "斯特鲁伊克",   // Struijk
        329: "罗多恩",   // Rodon
        330: "博格尔",   // Bogle
        331: "古德穆恩德松",   // Gudmundsson
        332: "尤斯蒂恩",   // Justin
        333: "博尔瑙",   // Bornauw
        334: "穆哈雷姆奥维奇",   // Muharemović
        335: "斯塔赫",   // Stach
        336: "奥卡福尔",   // Okafor
        337: "阿伦森",   // Aaronson
        338: "安帕杜",   // Ampadu
        339: "肖恩·朗斯塔夫",   // Longstaff
        340: "盖尔哈特",   // Gelhardt
        341: "尼翁托",   // Gnonto
        342: "哈里森",   // Harrison
        343: "亚梅斯",   // James
        344: "格鲁埃夫",   // Gruev
        345: "田中碧",   // Tanaka
        346: "多米尼克·卡尔弗特-勒温",   // Calvert-Lewin
        347: "恩梅查",   // Nmecha
        348: "皮罗埃",   // Piroe
        349: "马特奥·何塞",   // Mateo Joseph
        350: "阿利松",   // A.Becker
        351: "乔治·马马达什维利",   // Mamardashvili
        352: "沃奥德曼",   // Woodman
        353: "佩奇",   // Pecsi
        354: "雅罗斯",   // Jaros
        355: "戴维斯",   // Davies
        356: "维吉尔·范戴克",   // Virgil
        357: "杰雷米·弗林蓬",   // Frimpong
        358: "米洛斯·凯尔凯兹",   // Kerkez
        359: "戈梅兹",   // Gomez
        360: "布拉德利",   // Bradley
        361: "拉基",   // Lucky
        362: "雅凯",   // Jacquet
        363: "莱奥尼",   // Leoni
        364: "康斯坦丁诺斯·齐米卡斯",   // Tsimikas
        365: "拉姆塞",   // Ramsay
        366: "弗洛里安·维尔茨",   // Wirtz
        367: "科迪·加克波",   // Gakpo
        368: "多米尼克·索博斯洛伊",   // Szoboszlai
        369: "恩古莫哈",   // Ngumoha
        370: "费德里科·基耶萨",   // Chiesa
        371: "瑞安·赫拉芬贝赫",   // Gravenberch
        372: "亚历克西斯·麦卡利斯特",   // Mac Allister
        373: "柯蒂斯·琼斯",   // C.Jones
        374: "埃恩多",   // Endo
        375: "恩约尼",   // Nyoni
        376: "巴伊切蒂奇",   // Bajcetic
        377: "穆诺兹",   // Munoz
        378: "姆克科恩内尔",   // McConnell
        379: "亚历山大·伊萨克",   // Isak
        380: "雨果·埃基蒂克",   // Ekitiké
        381: "科乌马斯",   // Koumas
        382: "丹斯",   // Danns
        383: "哈维·埃利奥特",   // Elliott
        384: "多纳鲁马",   // Donnarumma
        385: "特拉福德",   // Trafford
        386: "马库斯·贝蒂内利",   // Bettinelli
        387: "尼科·奥赖利",   // O'Reilly
        388: "马克·格伊",   // Guéhi
        389: "努内斯",   // Matheus N.
        390: "鲁本·迪亚斯",   // Rúben
        391: "约什科·格瓦迪奥尔",   // Gvardiol
        392: "艾特·诺乌里",   // Aït-Nouri
        393: "胡桑诺夫",   // Khusanov
        394: "阿莱恩",   // Alleyne
        395: "里科·刘易斯",   // Lewis
        396: "雷斯",   // Vitor Reis
        397: "安托万·塞门约",   // Semenyo
        398: "菲尔·福登",   // Foden
        399: "拉扬·切尔基",   // Cherki
        400: "杰里米·多库",   // Doku
        401: "奥马尔·马尔穆什",   // Marmoush
        402: "罗德里戈",   // Rodrigo
        403: "萨维奥",   // Sávio
        404: "雷恩德斯",   // Reijnders
        405: "尼科·冈萨雷斯",   // N.Gonzalez
        406: "科瓦西克",   // Kovačić
        407: "埃切韦里",   // Echeverri
        408: "菲利普斯",   // Phillips
        409: "穆卡萨",   // Mukasa
        410: "蒙加",   // Monga
        411: "埃尔林·哈兰德",   // Haaland
        412: "拉姆梅恩斯",   // Lammens
        413: "巴因迪尔",   // Bayindir
        414: "赫阿托恩",   // Heaton
        415: "本杰明·多古",   // Dorgu
        416: "马泰斯·德里赫特",   // De Ligt
        417: "迪奥戈·达洛特",   // Dalot
        418: "哈里·马奎尔",   // Maguire
        419: "利桑德罗·马丁内斯",   // Martinez
        420: "莱尼·约罗",   // Yoro
        421: "赫阿韦恩",   // Heaven
        422: "诺塞尔·马兹拉维",   // Mazraoui
        423: "卢克·肖",   // Shaw
        424: "阿马斯",   // Amass
        425: "弗雷德里克松",   // Fredricson
        426: "布鲁诺·费尔南德斯",   // B.Fernandes
        427: "布莱恩·姆贝乌莫",   // Mbeumo
        428: "马特乌斯·库尼亚",   // Cunha
        429: "拉什福德",   // Rashford
        430: "梅森·芒特",   // Mount
        431: "阿马德·迪亚洛",   // Amad
        432: "科比·梅努",   // Mainoo
        433: "乌加特",   // Ugarte
        434: "弗莱彻",   // J.Fletcher
        435: "拉塞伊",   // Lacey
        436: "科利尔",   // Collyer
        437: "本迪托·曼塔托",   // Bendito Mantato
        438: "弗莱特赫埃尔",   // Fletcher
        439: "本杰明·塞斯科",   // Šeško
        440: "齐尔克泽",   // Zirkzee
        441: "奥比",   // Obi
        442: "尼克·波普",   // Pope
        443: "吉莱斯皮",   // Gillespie
        444: "亚乌埃恩",   // Jaouen
        445: "特亚瓦",   // Thiaw
        446: "法比安·沙尔",   // Schär
        447: "斯文·博特曼",   // Botman
        448: "丹·伯恩",   // Burn
        449: "刘易斯·霍尔",   // Hall
        450: "蒂诺·利夫拉门托",   // Livramento
        451: "亚历克斯·墨菲",   // A.Murphy
        452: "布鲁诺·吉马良斯",   // Bruno G.
        453: "哈维·巴恩斯",   // Barnes
        454: "布莱恩·埃兰加",   // Elanga
        455: "桑德罗·托纳利",   // Tonali
        456: "雅各布·拉姆齐",   // J.Ramsey
        457: "墨菲",   // J.Murphy
        458: "若埃林顿",   // Joelinton
        459: "刘易斯·米利",   // L.Miley
        460: "乔·威洛克",   // Willock
        461: "托乌雷",   // Touré
        462: "斯特乌尔",   // Steur
        463: "沃尔特马德",   // Woltemade
        464: "约安·维萨",   // Wissa
        465: "奥苏拉",   // Osula
        466: "尼夫",   // Neave
        467: "塞尔斯",   // Sels
        468: "约赫恩",   // John
        469: "威廉姆斯",   // N.Williams
        470: "莫拉托",   // Morato
        471: "米伦科维奇",   // Milenković
        472: "穆里略",   // Murillo
        473: "奥拉·艾纳",   // Aina
        474: "亚伊尔",   // Jair Cunha
        475: "萨沃纳",   // Savona
        476: "理查兹",   // O.Richards
        477: "阿布博特特",   // Abbott
        478: "内茨",   // Netz
        479: "宾登",   // Bindon
        480: "摩根·吉布斯-怀特",   // Gibbs-White
        481: "安德森",   // Anderson
        482: "赫德森-奥多伊",   // Hudson-Odoi
        483: "恩多耶",   // Ndoye
        484: "哈钦森",   // Hutchinson
        485: "巴克瓦",   // Bakwa
        486: "姆卡特埃",   // McAtee
        487: "多明格斯",   // Dominguez
        488: "萨恩加雷",   // I.Sangaré
        489: "耶茨",   // Yates
        490: "克里斯·伍德",   // Wood
        491: "耶苏斯",   // Igor Jesus
        492: "阿沃尼伊",   // Awoniyi
        493: "卡利穆埃恩多",   // Kalimuendo
        494: "古列尔莫·维卡里奥",   // Vicario
        495: "奥斯汀",   // Austin
        496: "基恩斯基",   // Kinsky
        497: "杜布拉夫卡",   // Dubravka
        498: "马科斯·塞内西",   // Senesi
        499: "波罗",   // Pedro Porro
        500: "克里斯蒂安·罗梅罗",   // Romero
        501: "丹索",   // Danso
        502: "安德鲁·罗伯逊",   // Robertson
        503: "米基·范德文",   // Van de Ven
        504: "武斯克奥维奇",   // Vuskovic
        505: "斯彭斯",   // Spence
        506: "德斯蒂尼·乌多吉",   // Udogie
        507: "菲利普斯",   // Phillips
        508: "戴维斯",   // Davies
        509: "拜菲尔德",   // Byfield
        510: "罗斯韦尔",   // Rowswell
        511: "苏萨",   // Souza
        512: "穆罕默德·库杜斯",   // Kudus
        513: "哈维",   // Xavi
        514: "特尔",   // Tel
        515: "詹姆斯·麦迪逊",   // Maddison
        516: "罗德里戈·本坦库尔",   // Bentancur
        517: "奥多贝尔",   // Odobert
        518: "萨尔",   // P.M.Sarr
        519: "加尔拉格埃尔",   // Gallagher
        520: "贝里瓦尔",   // Bergvall
        521: "德扬·库卢塞夫斯基",   // Kulusevski
        522: "阿尔奇·格雷",   // Gray
        523: "莫奥雷",   // Moore
        524: "奥卢塞西",   // Olusesi
        525: "马特乌斯·费尔南德斯",   // Fernandes
        526: "多米尼克·索兰克",   // Solanke
        527: "里沙利松",   // Richarlison
        528: "斯卡利特",   // Scarlett
        529: "罗宾·罗夫斯",   // Roefs
        530: "帕特森",   // Patterson
        531: "埃尔博尔格",   // Ellborg
        532: "巴拉德",   // Ballard
        533: "穆基埃莱",   // Mukiele
        534: "休姆",   // Hume
        535: "阿尔德莱特",   // Alderete
        536: "雷伊尼尔多",   // Reinildo
        537: "塞尔特",   // Seelt
        538: "耶尔德",   // Hjelde
        539: "奥尼恩",   // O'Nien
        540: "马苏库",   // Masuaku
        541: "梅乌尼埃尔",   // Meunier
        542: "勒费",   // E.Le Fée
        543: "迪亚拉",   // Diarra
        544: "克斯哈卡",   // Xhaka
        545: "萨迪基",   // Sadiki
        546: "西蒙·阿丁格拉",   // Adingra
        547: "芒德尔",   // Mundle
        548: "里格",   // Rigg
        549: "塔尔比",   // Talbi
        550: "乔赛林·塔比",   // Jocelin.T
        551: "阿恩古洛",   // N.Angulo
        552: "布罗贝伊",   // Brobbey
        553: "伊西多尔",   // Isidor
        554: "范·欧韦伦",   // Van Oevelen
        555: "马特特埃瓦斯",   // Matthews
        556: "塔尔格特特",   // Targett
        557: "克里斯托斯·佐利斯",   // Tzolis
        558: "施拉格尔",   // Schlager
        559: "巴姆巴",   // Bamba
        560: "佩恩德尔斯",   // Penders
        561: "阿恩塞尔米诺",   // Anselmino
        562: "马埃达",   // Maeda
        563: "莫里塔",   // Morita
        564: "施埃尔佩恩",   // Scherpen
        565: "萨恩加雷",   // M.Sangaré
        566: "贝尔纳多·席尔瓦",   // Silva
        567: "霍尔尼塞克",   // Horníček
        568: "巴尔科",   // Barco
        569: "贡萨洛",   // Gonzalo
        570: "帕拉西奥斯",   // Palacios
        571: "弗洛雷恩蒂诺",   // Florentino
        572: "佐拉基斯",   // Tzolakis
        573: "桑切斯",   // Sanchez
        574: "詹斯·耶尔托-达尔",   // Hjertø-Dahl
        575: "伊伦基",   // Yirenkyi
        576: "斯特罗德",   // Stroud
        577: "富安健洋",   // Tomiyasu
        578: "穆德尔伊克",   // Mudryk
        579: "阿劳霍",   // Araujo
        580: "查尔斯",   // Charles
        581: "迪奥曼德",   // Diomande
        582: "布赖恩·马乔",   // Madjo
        583: "查瓦利亚",   // Chavarria
        584: "古斯塔沃·哈默",   // Hamer
        585: "卢卡斯·赫林顿",   // Herrington
        586: "门迪",   // Mendy
        587: "鲁利",   // Rulli
        588: "阿南·哈利利",   // Khalaili
        589: "古尔纳-杜阿特",   // Gourna-Douath
        590: "本达",   // Benda
        591: "胡里奥·恩西索",   // Enciso
        592: "瓦塔拉",   // Ouattara
        593: "阿马尔·德迪奇",   // Dedić
        594: "达维德",   // David
        595: "扎维尔·戈佐",   // Gozo
        596: "马特奥·鲁杰",   // Ruggeri
        597: "铃木彩艳",   // Suzuki
        598: "埃尔韦迪",   // Elvedi
        599: "切里夫",   // Cherif
        600: "奥斯曼",   // Osman
        601: "维尔利阿姆斯·巴尔内特特",   // Williams-Barnett
        602: "胡姆弗雷伊斯",   // Humphreys
        603: "利埃诺乌",   // Lienou
        604: "克雷斯韦尔",   // Cresswell
        605: "马利克·亚尔库耶",   // Yalcouyé
        606: "罗",   // Rowe
        607: "林奇",   // Lynch
        608: "耶布比松",   // Jebbison
        609: "什阿哈尔",   // Shahar
        610: "德·富热罗尔",   // De Fougerolles
        611: "万·比萨卡",   // Wan-Bissaka
        612: "梅特阿利埃",   // Methalie
        613: "朱尔斯·阿霍卡",   // Ahoka
        614: "贾恩·哈贾姆",   // Hadjam
        615: "格雷戈里奥",   // Di Gregorio
        616: "博瓦德迪",   // Bouaddi
        617: "曹",   // Cho
        618: "格雷茨卡",   // Goretzka
        619: "帕拉西奥斯",   // Palacios
        620: "迪乌夫",   // Diouf
        621: "姆卡伊多奥",   // McAidoo
        622: "布雷思韦特",   // Braithwaite
        623: "丹尼尔·本特利",   // Bentley
        624: "阿马里奥·科齐尔-杜伯里",   // Cozier-Duberry
        625: "卡伊尔恩斯",   // Cairns
        626: "泽帕",   // Zepa
        627: "巴尔科拉",   // Barcola
        628: "阿兰",   // Allan
        629: "泽特特雷尔",   // Zetterer
        630: "泰勒·哈伍德-贝利斯",   // Harwood-Bellis
        631: "易卜拉欣·姆巴耶",   // Mbaye
        632: "阿恩萨赫",   // Ansah
        633: "霍内斯特·阿哈诺尔",   // Ahanor
        634: "费尔纳恩德兹·帕尔多",   // Fernandez-Pardo
        635: "拉尔松",   // Larsson
        636: "阿恩格尔",   // Ángel
        637: "瓦兹",   // Vaz
        638: "诺尔托恩·库弗弗伊",   // Norton-Cuffy
        639: "切马·安德烈斯",   // Andrés
        640: "弗莱明",   // Flemming
        641: "巴尔德",   // Bard
        642: "索尔巴·托马斯",   // Thomas
        643: "本·奇尔维尔",   // Chilwell
        644: "尤里恩·廷贝尔",   // Timber
        645: "莫扎基蒂斯",   // Mouzakitis
        646: "马利克·福法纳",   // Fofana
        647: "达里奥·奥索里奥",   // Osorio
        648: "巴霍亚",   // Bahoya
        649: "梅特兰-奈尔斯",   // Maitland-Niles
        650: "阿弗费恩格鲁贝尔",   // Affengruber
        651: "胡安·安古洛",   // J.Angulo
        652: "阿泽兹",   // Azeez
        653: "桑巴",   // Samba
        654: "格雷厄姆",   // Graham
        655: "格博霍",   // Gboho
        656: "姆富尼",   // Mfuni
        657: "马特乌斯·努内斯",   // Nunes
        658: "易卜拉欣·奥斯曼",   // Ibrahim
        659: "米莱伊",   // Miley
        660: "弗雷德里克",   // Fredrick
        661: "巴尔科姆贝",   // Balcombe
        662: "贾祖里",   // Nicoll-Jazuli
        663: "皮瓦斯",   // Pivas
        664: "萨利亚",   // Salia
        665: "米尔斯",   // Mills
        666: "汤普森",   // Thompson
        667: "赖特",   // Wright
    ]

    /// web_name → 中文全名（二级回退；仅收匹配到的，重姓碰撞时以最后一个为准）
    private static let zhByName: [String: String] = [
        "Aaronson": "阿伦森",
        "Adams": "亚当斯",
        "Aina": "奥拉·艾纳",
        "Ajer": "阿耶尔",
        "Alcaraz": "阿尔卡拉斯",
        "Amad": "阿马德·迪亚洛",
        "Ampadu": "安帕杜",
        "Anderson": "安德森",
        "Araujo": "阿劳霍",
        "Awoniyi": "阿沃尼伊",
        "Ayari": "扬库·阿亚里",
        "Baleba": "卡洛斯·巴莱巴",
        "Ballard": "巴拉德",
        "Barkley": "罗斯·巴克利",
        "Barnes": "哈维·巴恩斯",
        "Barry": "巴里",
        "Bassey": "巴塞",
        "Bentancur": "罗德里戈·本坦库尔",
        "Berge": "贝尔赫",
        "Bergvall": "贝里瓦尔",
        "Beto": "贝托",
        "Bettinelli": "马库斯·贝蒂内利",
        "Bijol": "比约尔",
        "Bobb": "奥斯卡·鲍勃",
        "Bogle": "博格尔",
        "Botman": "斯文·博特曼",
        "Branthwaite": "贾拉德·布兰斯韦特",
        "Buendía": "布恩迪亚",
        "Burn": "丹·伯恩",
        "C.Jones": "柯蒂斯·琼斯",
        "Caicedo": "莫伊塞斯·凯塞多",
        "Cairney": "卡尔尼",
        "Calafiori": "里卡多·卡拉菲奥里",
        "Calvert-Lewin": "多米尼克·卡尔弗特-勒温",
        "Carvalho": "卡瓦略",
        "Cash": "梅米·卡什",
        "Castagne": "卡斯塔涅",
        "Chalobah": "特雷沃·查洛巴",
        "Cherki": "拉扬·切尔基",
        "Chiesa": "费德里科·基耶萨",
        "Christie": "瑞安·克里斯蒂",
        "Colwill": "利维·科尔威尔",
        "Cook": "刘易斯·库克",
        "Cunha": "马特乌斯·库尼亚",
        "Dalot": "迪奥戈·达洛特",
        "Damsgaard": "达姆斯高",
        "Danso": "丹索",
        "Darlow": "达洛",
        "De Ligt": "马泰斯·德里赫特",
        "Delap": "利亚姆·德拉普",
        "Devenny": "德文尼",
        "Digne": "卢卡斯·迪涅",
        "Diop": "迪奥普",
        "Diouf": "迪乌夫",
        "Disasi": "阿克塞尔·迪萨西",
        "Doku": "杰里米·多库",
        "Dominguez": "多明格斯",
        "Dorgu": "本杰明·多古",
        "Doucouré": "阿卜杜拉耶·杜库雷",
        "Dunk": "刘易斯·邓克",
        "E.Le Fée": "勒费",
        "Ekitiké": "雨果·埃基蒂克",
        "Elanga": "布莱恩·埃兰加",
        "Elliott": "哈维·埃利奥特",
        "Enciso": "胡里奥·恩西索",
        "Enzo": "恩佐·费尔南德斯",
        "Esse": "埃塞",
        "Estêvão": "埃斯特旺·威廉",
        "Evanilson": "达尼洛·埃瓦尼松",
        "Eze": "埃贝雷奇·埃泽",
        "Ferguson": "埃文·弗格森",
        "Fernandes": "马特乌斯·费尔南德斯",
        "Foden": "菲尔·福登",
        "Frimpong": "杰雷米·弗林蓬",
        "Gabriel": "加布里埃尔·多斯·桑托斯",
        "Gakpo": "科迪·加克波",
        "Garnacho": "亚历杭德罗·加纳乔",
        "Garner": "詹姆斯·加纳",
        "George": "泰里克·乔治",
        "Georginio": "鲁特",
        "Gibbs-White": "摩根·吉布斯-怀特",
        "Gnonto": "尼翁托",
        "Gravenberch": "瑞安·赫拉芬贝赫",
        "Gray": "阿尔奇·格雷",
        "Grealish": "杰克·格里利什",
        "Gruev": "格鲁埃夫",
        "Gusto": "马洛·古斯托",
        "Guéhi": "马克·格伊",
        "Gvardiol": "约什科·格瓦迪奥尔",
        "Gyökeres": "维克托·哲凯赖什",
        "Haaland": "埃尔林·哈兰德",
        "Hall": "刘易斯·霍尔",
        "Harrison": "哈里森",
        "Havertz": "凯·哈弗茨",
        "Henry": "里科·亨利",
        "Hinshelwood": "兰克·辛谢尔伍德",
        "Hudson-Odoi": "赫德森-奥多伊",
        "Hume": "休姆",
        "Isak": "亚历山大·伊萨克",
        "Isidor": "伊西多尔",
        "Iwobi": "伊沃比",
        "J.Ramsey": "雅各布·拉姆齐",
        "Janelt": "亚内尔特",
        "Jensen": "马蒂亚斯·延斯滕",
        "Joelinton": "若埃林顿",
        "João Pedro": "若昂·佩德罗",
        "Kamada": "镰田大地",
        "Kayode": "卡约德",
        "Kerkez": "米洛斯·凯尔凯兹",
        "Kluivert": "贾斯汀·克鲁伊维特",
        "Konsa": "埃兹里·孔萨",
        "Kudus": "穆罕默德·库杜斯",
        "Kulusevski": "德扬·库卢塞夫斯基",
        "Lacroix": "拉格朗日",
        "Leno": "贝恩德·莱诺",
        "Lewis": "里科·刘易斯",
        "Lewis-Potter": "刘易斯-波特",
        "Lewis-Skelly": "迈尔斯·刘易斯-斯凯利",
        "Livramento": "蒂诺·利夫拉门托",
        "Longstaff": "肖恩·朗斯塔夫",
        "Mac Allister": "亚历克西斯·麦卡利斯特",
        "Maddison": "詹姆斯·麦迪逊",
        "Madueke": "诺尼·马杜埃凯",
        "Maguire": "哈里·马奎尔",
        "Mainoo": "科比·梅努",
        "Mamardashvili": "乔治·马马达什维利",
        "Marmoush": "奥马尔·马尔穆什",
        "Martinelli": "加布里埃尔·马丁内利",
        "Mateta": "让-菲利普·马特塔",
        "Mazraoui": "诺塞尔·马兹拉维",
        "Mbeumo": "布莱恩·姆贝乌莫",
        "McGinn": "约翰·麦金",
        "McNeil": "德怀特·麦克尼尔",
        "Merino": "米克尔·梅里诺",
        "Milenković": "米伦科维奇",
        "Mitchell": "泰里克·米切尔",
        "Mitoma": "三笘薫",
        "Mosquera": "德雷·莫斯克拉",
        "Mount": "梅森·芒特",
        "Mundle": "芒德尔",
        "Muniz": "穆尼兹",
        "Murillo": "穆里略",
        "Mykolenko": "亚历克斯·墨菲",
        "N.Jackson": "尼古拉·杰克逊",
        "N.Williams": "威廉姆斯",
        "Ndiaye": "恩迪亚耶",
        "Neto": "佩德罗·内托",
        "Nunes": "马特乌斯·努内斯",
        "Nwaneri": "伊桑·恩瓦内里",
        "Núñez": "达尔文·努涅斯",
        "O'Brien": "奥布莱恩",
        "O'Nien": "奥尼恩",
        "O'Reilly": "尼科·奥赖利",
        "Odobert": "奥多贝尔",
        "Onana": "奥纳纳",
        "Ouattara": "瓦塔拉",
        "Pickford": "乔丹·皮克福德",
        "Pinnock": "伊桑·平诺克",
        "Piroe": "皮罗埃",
        "Pope": "尼克·波普",
        "Raya": "戴维·拉亚",
        "Reijnders": "雷恩德斯",
        "Rice": "德克兰·赖斯",
        "Richards": "理查兹",
        "Richarlison": "里沙利松",
        "Rigg": "里格",
        "Robertson": "安德鲁·罗伯逊",
        "Robinson": "安东尼·罗宾逊",
        "Rodríguez": "罗德里格斯",
        "Rogers": "摩根·罗杰斯",
        "Romero": "克里斯蒂安·罗梅罗",
        "Rúben": "鲁本·迪亚斯",
        "Saka": "布卡约·萨卡",
        "Saliba": "威廉·萨利巴",
        "Sarr": "马姆杜·萨尔",
        "Schade": "沙德",
        "Schär": "法比安·沙尔",
        "Sels": "塞尔斯",
        "Semenyo": "安托万·塞门约",
        "Senesi": "马科斯·塞内西",
        "Shaw": "卢克·肖",
        "Silva": "贝尔纳多·席尔瓦",
        "Smith": "亚当·史密斯",
        "Solanke": "多米尼克·索兰克",
        "Spence": "斯彭斯",
        "Strand Larsen": "斯特兰德·拉森",
        "Struijk": "斯特鲁伊克",
        "Szoboszlai": "多米尼克·索博斯洛伊",
        "Talbi": "塔尔比",
        "Tanaka": "田中碧",
        "Tarkowski": "詹姆斯·塔科夫斯基",
        "Tavernier": "塔维尼尔",
        "Tel": "特尔",
        "Tete": "肯尼·特特",
        "Thiago": "蒂亚戈",
        "Tielemans": "尤里·蒂勒曼斯",
        "Timber": "尤里恩·廷贝尔",
        "Tonali": "桑德罗·托纳利",
        "Trafford": "特拉福德",
        "Travers": "特拉弗斯",
        "Tsimikas": "康斯坦丁诺斯·齐米卡斯",
        "Udogie": "德斯蒂尼·乌多吉",
        "Van Hecke": "扬·范赫克",
        "Van de Ven": "米基·范德文",
        "Verbruggen": "巴特·费布鲁亨",
        "Vicario": "古列尔莫·维卡里奥",
        "Virgil": "维吉尔·范戴克",
        "Watkins": "奥利·沃特金斯",
        "Watson": "沃森",
        "Wharton": "亚当·沃顿",
        "White": "本·怀特",
        "Willock": "乔·威洛克",
        "Wirtz": "弗洛里安·维尔茨",
        "Wissa": "约安·维萨",
        "Wood": "克里斯·伍德",
        "Yates": "耶茨",
        "Yoro": "莱尼·约罗",
        "Zirkzee": "齐尔克泽",
        "Zubimendi": "马丁·祖比门迪",
        "Šeško": "本杰明·塞斯科",
    ]

    /// 取中文名；无匹配返回 nil。
    /// 覆盖层优先：覆盖层（调试期开发者自定义）胜出；id 维度仍先于 name 维度。
    /// 仅改此函数接入覆盖层，不改动下方 zhById / zhByName 字面量。
    static func zh(for player: PlayerLite) -> String? {
        let o = PlayerNameStore.current
        if let pid = player.id, let c = (o.byId[pid] ?? zhById[pid]) { return c }
        if let c = (o.byName[player.name] ?? zhByName[player.name]) { return c }
        return nil
    }

    /// 仅取内置（zhById）中文名，不含覆盖层；供调试面板判断「是否冗余覆盖」做基线。
    static func builtInName(forId id: Int) -> String? { zhById[id] }

    /// 维护用：给定一批 FPL element id（现役球员），返回映射表缺失中文名的那些（已排序）。
    static func missing(ids: [Int]) -> [Int] {
        ids.filter { zhById[$0] == nil }.sorted()
    }

    /// 维护用（兼容 web_name 维度）：给定一批 web_name，返回缺失中文名的那些（已排序去重）。
    static func missing(from webNames: [String]) -> [String] {
        Set(webNames).subtracting(zhByName.keys).sorted()
    }
}

extension PlayerLite {
    /// 中文名（无匹配为 nil）
    var nameZh: String? { PlayerNameMap.zh(for: self) }

    /// 按语言偏好返回显示名：中文模式下优先中文（无则回退英文），英文模式恒为英文原名
    func displayName(chinese: Bool) -> String {
        chinese ? (nameZh ?? name) : name
    }
}
