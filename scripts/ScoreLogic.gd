extends RefCounted
class_name ScoreLogic

const CATEGORIES := [
    "ones", "twos", "threes", "fours", "fives", "sixes",
    "three_of_a_kind", "four_of_a_kind", "full_house",
    "small_straight", "large_straight",
    "yahtzee"
]

# Alias for use in other scripts
const ALL_CATEGORIES := CATEGORIES

static func count_faces(dice: Array[int]) -> Dictionary:
    var counts: Dictionary = {}
    for d in dice:
        counts[d] = counts.get(d, 0) + 1
    return counts

static func score_upper(dice: Array[int], face: int) -> int:
    var sum := 0
    for d in dice:
        if d == face:
            sum += d
    return sum

static func is_n_of_a_kind(dice: Array[int], n: int) -> bool:
    var counts := count_faces(dice)
    for c in counts.values():
        if c >= n:
            return true
    return false

static func is_full_house(dice: Array[int]) -> bool:
    var counts := count_faces(dice).values()
    counts.sort()
    return counts == [2, 3]

static func _get_unique_sorted(dice: Array[int]) -> Array[int]:
    var seen: Dictionary = {}
    var result: Array[int] = []
    for d in dice:
        if not seen.has(d):
            seen[d] = true
            result.append(d)
    result.sort()
    return result

static func is_small_straight(dice: Array[int]) -> bool:
    var unique := _get_unique_sorted(dice)
    var straights := [
        [1,2,3,4],
        [2,3,4,5],
        [3,4,5,6]
    ]
    for s in straights:
        var ok := true
        for v in s:
            if v not in unique:
                ok = false
                break
        if ok:
            return true
    return false

static func is_large_straight(dice: Array[int]) -> bool:
    var unique := _get_unique_sorted(dice)
    return unique == [1,2,3,4,5] or unique == [2,3,4,5,6]

static func is_yahtzee(dice: Array[int]) -> bool:
    var counts := count_faces(dice)
    return 5 in counts.values()

static func score_all(dice: Array[int]) -> Dictionary:
    var result: Dictionary = {}
    result["ones"] = score_upper(dice, 1)
    result["twos"] = score_upper(dice, 2)
    result["threes"] = score_upper(dice, 3)
    result["fours"] = score_upper(dice, 4)
    result["fives"] = score_upper(dice, 5)
    result["sixes"] = score_upper(dice, 6)

    var total := 0
    for d in dice: total += d

    result["three_of_a_kind"] = total if is_n_of_a_kind(dice, 3) else 0
    result["four_of_a_kind"] = total if is_n_of_a_kind(dice, 4) else 0
    result["full_house"] = 25 if is_full_house(dice) else 0
    result["small_straight"] = 30 if is_small_straight(dice) else 0
    result["large_straight"] = 40 if is_large_straight(dice) else 0
    result["yahtzee"] = 50 if is_yahtzee(dice) else 0

    return result

static func calculate_score(category: String, dice: Array) -> int:
    # Convert to Array[int] if needed
    var int_dice: Array[int] = []
    for d in dice:
        int_dice.append(int(d))
    
    var scores := score_all(int_dice)
    return int(scores.get(category, 0))
