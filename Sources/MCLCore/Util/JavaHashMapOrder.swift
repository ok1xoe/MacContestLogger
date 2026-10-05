/// Iteration order of Java's `HashMap<String, …>` (JDK 21), where it leaks into UI text
/// (`LogWarnings`).
///
/// Holds only the **keys and their ordering**; the caller carries the values separately (e.g.
/// `JavaLinkedMap`). Emulates exactly what the Java order depends on:
/// - `String.hashCode` by UTF-16 units with a wrapping `int`, spreading `h ^ (h >>> 16)`,
///   bucket `(n - 1) & hash`, a `null` key has hash 0;
/// - a table of 16 buckets, threshold 0.75, doubling with splitting a bucket into "lo"/"hi" while preserving
///   relative order;
/// - **`put` and `computeIfAbsent` differ**: `put` appends the node to the end of the bucket and grows the table
///   only *after* insertion (`++size > threshold`), `computeIfAbsent` adds the node to the **front** of the bucket
///   and grows *before* insertion (`size > threshold`) — 13 keys give `put` a table of 32,
///   `computeIfAbsent` 16, and hence a different order (measured);
/// - tree bins: from 8 nodes in a bin (9 for `put`) and a table ≥ 64 the bin is converted to
///   a red-black tree (a smaller table is grown instead). Iteration continues along the linked
///   list, but the tree root is moved to the front of the bin and a new tree node is placed
///   right after its parent. On resize a tree bin is split and with ≤ 6 nodes it reverts to a list.
///   Copy of `HashMap.TreeNode` (`treeify`, `putTreeVal`, `balanceInsertion`, rotations, `split`,
///   `moveRootToFront`). Key comparison in the tree is `String.compareTo` (UTF-16).
///
/// The only place where Java is not deterministic: a `null` key in a tree bin together with another
/// key with hash 0 (`""`) — Java decides there by `System.identityHashCode`. Here `null` always
/// goes left. In `LogWarnings` `null` can only be an exchange field id, and such maps have a few
/// keys (a tree arises only from 8 keys in one bin).
///
/// The Java code this emulates does not use key removal, so it is not here.
struct JavaHashMapOrder: Sendable {

    private struct Node: Sendable {
        let key: String?
        let units: [UInt16]?
        let hash: Int32
        var next: Int?
        // tree links (`TreeNode`)
        var isTree = false
        var parent: Int?
        var left: Int?
        var right: Int?
        var prev: Int?
        var red = false
    }

    /// Key for lookup by UTF-16 units (`nil` = Java `null`).
    private struct Lookup: Hashable, Sendable {
        let units: [UInt16]?
    }

    private static let treeifyThreshold = 8
    private static let untreeifyThreshold = 6
    private static let minTreeifyCapacity = 64

    private var nodes: [Node] = []
    private var table: [Int?] = []
    private var threshold = 0
    private var index: [Lookup: Int] = [:]

    init() {}

    /// Number of keys.
    var count: Int { nodes.count }

    /// Length of the Java table (0 = not yet allocated).
    var tableLength: Int { table.count }

    /// Number of bins that are currently a tree (for the test against Java).
    var treeBinCount: Int {
        var trees = 0
        for case let head? in table where nodes[head].isTree { trees += 1 }
        return trees
    }

    /// Keys in Java iteration order (`keySet()`, `entrySet()`, `forEach`).
    var keys: [String?] {
        var out: [String?] = []
        out.reserveCapacity(nodes.count)
        for head in table {
            var e = head
            while let i = e {
                out.append(nodes[i].key)
                e = nodes[i].next
            }
        }
        return out
    }

    func contains(_ key: String?) -> Bool {
        index[Lookup(units: key.map { Array($0.utf16) })] != nil
    }

    /// Java `String.hashCode()`: `s[0]*31^(n-1) + … + s[n-1]` by UTF-16, wrapping `int`.
    static func hashCode(_ text: String) -> Int32 {
        var h: Int32 = 0
        for unit in text.utf16 {
            h = 31 &* h &+ Int32(unit)
        }
        return h
    }

    /// `HashMap.hash`: `null` → 0, otherwise `h ^ (h >>> 16)`.
    private static func spread(_ key: String?) -> Int32 {
        guard let key else { return 0 }
        let h = UInt32(bitPattern: hashCode(key))
        return Int32(bitPattern: h ^ (h >> 16))
    }

    private func bucket(_ hash: Int32, _ length: Int) -> Int {
        Int(UInt32(bitPattern: hash) & UInt32(length - 1))
    }

    // MARK: - Insertion

    /// Java `HashMap.put` (for an existing key the order does not change).
    mutating func put(_ key: String?) {
        let lookup = Lookup(units: key.map { Array($0.utf16) })
        if index[lookup] != nil { return }
        let hash = Self.spread(key)
        if table.isEmpty { resize() }
        let n = table.count
        let i = bucket(hash, n)
        let x = newNode(key, lookup, hash)
        if let first = table[i] {
            if nodes[first].isTree {
                putTreeVal(first, x)
            } else {
                // to the end of the list; binCount = number of nodes before the last
                var p = first
                var binCount = 0
                while let next = nodes[p].next {
                    p = next
                    binCount += 1
                }
                nodes[p].next = x
                if binCount >= Self.treeifyThreshold - 1 { treeifyBin(hash) }
            }
        } else {
            table[i] = x
        }
        if nodes.count > threshold { resize() }
    }

    /// Java `HashMap.computeIfAbsent` with a function that returns a non-`null` value.
    ///
    /// Note: the threshold is checked **before the key lookup**, so the table grows even for a call with a key
    /// that is already in the map (13 keys in a table of 16 and another `computeIfAbsent` of anything → 32).
    mutating func computeIfAbsent(_ key: String?) {
        // growth before insertion: `size > threshold` (size without the new key)
        if nodes.count > threshold || table.isEmpty { resize() }
        let lookup = Lookup(units: key.map { Array($0.utf16) })
        if index[lookup] != nil { return }
        let hash = Self.spread(key)
        let n = table.count
        let i = bucket(hash, n)
        let first = table[i]
        if let first, nodes[first].isTree {
            let x = newNode(key, lookup, hash)
            putTreeVal(first, x)
            return
        }
        var binCount = 0
        var e = first
        while let j = e {
            binCount += 1
            e = nodes[j].next
        }
        let x = newNode(key, lookup, hash)
        nodes[x].next = first
        table[i] = x
        if binCount >= Self.treeifyThreshold - 1 { treeifyBin(hash) }
    }

    private mutating func newNode(_ key: String?, _ lookup: Lookup, _ hash: Int32) -> Int {
        nodes.append(Node(key: key, units: lookup.units, hash: hash))
        let i = nodes.count - 1
        index[lookup] = i
        return i
    }

    // MARK: - Table growth

    private mutating func resize() {
        let oldTable = table
        let oldCap = oldTable.count
        let newCap: Int
        if oldCap > 0 {
            newCap = oldCap << 1
            threshold <<= 1
        } else {
            newCap = 16
            threshold = 12
        }
        table = Array(repeating: nil, count: newCap)
        for j in 0..<oldCap {
            guard let e = oldTable[j] else { continue }
            if nodes[e].next == nil {
                table[bucket(nodes[e].hash, newCap)] = e
            } else if nodes[e].isTree {
                split(e, j, oldCap)
            } else {
                var loHead: Int?, loTail: Int?, hiHead: Int?, hiTail: Int?
                var cur: Int? = e
                while let c = cur {
                    let next = nodes[c].next
                    if UInt32(bitPattern: nodes[c].hash) & UInt32(oldCap) == 0 {
                        if let t = loTail { nodes[t].next = c } else { loHead = c }
                        loTail = c
                    } else {
                        if let t = hiTail { nodes[t].next = c } else { hiHead = c }
                        hiTail = c
                    }
                    cur = next
                }
                if let t = loTail {
                    nodes[t].next = nil
                    table[j] = loHead
                }
                if let t = hiTail {
                    nodes[t].next = nil
                    table[j + oldCap] = hiHead
                }
            }
        }
    }

    // MARK: - Tree bins (`HashMap.TreeNode`)

    private mutating func treeifyBin(_ hash: Int32) {
        let n = table.count
        if n < Self.minTreeifyCapacity {
            resize()
            return
        }
        let i = bucket(hash, n)
        guard let head = table[i] else { return }
        var tail: Int?
        var e: Int? = head
        while let c = e {
            nodes[c].isTree = true
            nodes[c].parent = nil
            nodes[c].left = nil
            nodes[c].right = nil
            nodes[c].red = false
            nodes[c].prev = tail
            tail = c
            e = nodes[c].next
        }
        treeify(head)
    }

    /// `String.compareTo` by UTF-16 (sign only).
    private func compare(_ a: [UInt16], _ b: [UInt16]) -> Int {
        for (x, y) in zip(a, b) where x != y {
            return Int(x) - Int(y)
        }
        return a.count - b.count
    }

    /// Insertion direction of `x` relative to node `p` (`treeify` / `putTreeVal`): hash, then `compareTo`,
    /// on a tie `tieBreakOrder` (for a `null` key Java uses `identityHashCode`, here left).
    private func direction(_ x: Int, _ p: Int) -> Int {
        let h = nodes[x].hash
        let ph = nodes[p].hash
        if ph > h { return -1 }
        if ph < h { return 1 }
        if let k = nodes[x].units, let pk = nodes[p].units {
            let d = compare(k, pk)
            if d != 0 { return d }
        }
        return -1
    }

    private mutating func treeify(_ head: Int) {
        var root: Int?
        var x: Int? = head
        while let c = x {
            let next = nodes[c].next
            nodes[c].left = nil
            nodes[c].right = nil
            if let r = root {
                var p = r
                while true {
                    let dir = direction(c, p)
                    let child = dir <= 0 ? nodes[p].left : nodes[p].right
                    if let child {
                        p = child
                    } else {
                        nodes[c].parent = p
                        if dir <= 0 { nodes[p].left = c } else { nodes[p].right = c }
                        root = balanceInsertion(r, c)
                        break
                    }
                }
            } else {
                nodes[c].parent = nil
                nodes[c].red = false
                root = c
            }
            x = next
        }
        if let root { moveRootToFront(root) }
    }

    private func rootOf(_ node: Int) -> Int {
        var r = node
        while let p = nodes[r].parent { r = p }
        return r
    }

    private mutating func putTreeVal(_ first: Int, _ x: Int) {
        nodes[x].isTree = true
        let root = rootOf(first)
        var p = root
        while true {
            let dir = direction(x, p)
            let child = dir <= 0 ? nodes[p].left : nodes[p].right
            if let child {
                p = child
                continue
            }
            let xpn = nodes[p].next
            nodes[x].next = xpn
            if dir <= 0 { nodes[p].left = x } else { nodes[p].right = x }
            nodes[p].next = x
            nodes[x].parent = p
            nodes[x].prev = p
            if let xpn { nodes[xpn].prev = x }
            moveRootToFront(balanceInsertion(root, x))
            return
        }
    }

    private mutating func moveRootToFront(_ root: Int) {
        let i = bucket(nodes[root].hash, table.count)
        let first = table[i]
        guard first != root else { return }
        table[i] = root
        let rp = nodes[root].prev
        if let rn = nodes[root].next { nodes[rn].prev = rp }
        if let rp { nodes[rp].next = nodes[root].next }
        if let first { nodes[first].prev = root }
        nodes[root].next = first
        nodes[root].prev = nil
    }

    private mutating func split(_ head: Int, _ index: Int, _ bit: Int) {
        var loHead: Int?, loTail: Int?, hiHead: Int?, hiTail: Int?
        var lc = 0, hc = 0
        var e: Int? = head
        while let c = e {
            let next = nodes[c].next
            nodes[c].next = nil
            if UInt32(bitPattern: nodes[c].hash) & UInt32(bit) == 0 {
                nodes[c].prev = loTail
                if let t = loTail { nodes[t].next = c } else { loHead = c }
                loTail = c
                lc += 1
            } else {
                nodes[c].prev = hiTail
                if let t = hiTail { nodes[t].next = c } else { hiHead = c }
                hiTail = c
                hc += 1
            }
            e = next
        }
        if let lo = loHead {
            if lc <= Self.untreeifyThreshold {
                untreeify(lo)
                table[index] = lo
            } else {
                table[index] = lo
                if hiHead != nil { treeify(lo) }
            }
        }
        if let hi = hiHead {
            if hc <= Self.untreeifyThreshold {
                untreeify(hi)
                table[index + bit] = hi
            } else {
                table[index + bit] = hi
                if loHead != nil { treeify(hi) }
            }
        }
    }

    /// Java `untreeify` builds new plain nodes in the same order.
    private mutating func untreeify(_ head: Int) {
        var e: Int? = head
        while let c = e {
            nodes[c].isTree = false
            nodes[c].parent = nil
            nodes[c].left = nil
            nodes[c].right = nil
            nodes[c].prev = nil
            nodes[c].red = false
            e = nodes[c].next
        }
    }

    private mutating func rotateLeft(_ root: Int, _ p: Int) -> Int {
        var root = root
        guard let r = nodes[p].right else { return root }
        let rl = nodes[r].left
        nodes[p].right = rl
        if let rl { nodes[rl].parent = p }
        let pp = nodes[p].parent
        nodes[r].parent = pp
        if let pp {
            if nodes[pp].left == p { nodes[pp].left = r } else { nodes[pp].right = r }
        } else {
            root = r
            nodes[r].red = false
        }
        nodes[r].left = p
        nodes[p].parent = r
        return root
    }

    private mutating func rotateRight(_ root: Int, _ p: Int) -> Int {
        var root = root
        guard let l = nodes[p].left else { return root }
        let lr = nodes[l].right
        nodes[p].left = lr
        if let lr { nodes[lr].parent = p }
        let pp = nodes[p].parent
        nodes[l].parent = pp
        if let pp {
            if nodes[pp].right == p { nodes[pp].right = l } else { nodes[pp].left = l }
        } else {
            root = l
            nodes[l].red = false
        }
        nodes[l].right = p
        nodes[p].parent = l
        return root
    }

    private mutating func balanceInsertion(_ root: Int, _ start: Int) -> Int {
        var root = root
        var x = start
        nodes[x].red = true
        while true {
            guard var xp = nodes[x].parent else {
                nodes[x].red = false
                return x
            }
            guard nodes[xp].red, var xpp = nodes[xp].parent else { return root }
            if nodes[xpp].left == xp {
                if let xppr = nodes[xpp].right, nodes[xppr].red {
                    nodes[xppr].red = false
                    nodes[xp].red = false
                    nodes[xpp].red = true
                    x = xpp
                } else {
                    var xpOpt: Int? = xp
                    var xppOpt: Int? = xpp
                    if nodes[xp].right == x {
                        x = xp
                        root = rotateLeft(root, x)
                        xpOpt = nodes[x].parent
                        xppOpt = xpOpt.flatMap { nodes[$0].parent }
                    }
                    if let p = xpOpt {
                        xp = p
                        nodes[xp].red = false
                        if let pp = xppOpt {
                            xpp = pp
                            nodes[xpp].red = true
                            root = rotateRight(root, xpp)
                        }
                    }
                }
            } else {
                if let xppl = nodes[xpp].left, nodes[xppl].red {
                    nodes[xppl].red = false
                    nodes[xp].red = false
                    nodes[xpp].red = true
                    x = xpp
                } else {
                    var xpOpt: Int? = xp
                    var xppOpt: Int? = xpp
                    if nodes[xp].left == x {
                        x = xp
                        root = rotateRight(root, x)
                        xpOpt = nodes[x].parent
                        xppOpt = xpOpt.flatMap { nodes[$0].parent }
                    }
                    if let p = xpOpt {
                        xp = p
                        nodes[xp].red = false
                        if let pp = xppOpt {
                            xpp = pp
                            nodes[xpp].red = true
                            root = rotateLeft(root, xpp)
                        }
                    }
                }
            }
        }
    }
}
