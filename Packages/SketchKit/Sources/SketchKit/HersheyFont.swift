/// Single-stroke vector font for hand-drawn labels.
///
/// Data: Hershey "futural" (Simplex) in JHF format — public domain, created
/// by A.V. Hershey at the US National Bureau of Standards; embedded so
/// SketchKit needs no bundle resources or dependencies. ASCII 32–126.
/// Long term, user-drawn glyphs (SPEC §7) feed the same `[[SketchPoint]]`
/// slot; this font is the bootstrap typeface.
///
/// JHF line format: cols 0–4 glyph id (unused), 5–7 vertex-pair count, then
/// pairs of chars encoding coordinates as `charCode - 'R'`; the first pair is
/// the left/right margin, and the pair " R" means pen-up.
public struct HersheyFont: Sendable {
    public struct Glyph: Sendable {
        public let leftMargin: Double
        public let rightMargin: Double
        /// Pen strokes in font units. y grows downward; caps span y −12…9
        /// (21 units, baseline at y = 9).
        public let strokes: [[SketchPoint]]
    }

    /// Height of the caps box in font units (y −12…9).
    public static let unitsPerEm: Double = 21

    public let glyphs: [Glyph]

    /// The bundled futural font, parsed once.
    public static let futural = HersheyFont(jhf: futuralJHF)

    public init(jhf: String) {
        var parsed = [Glyph]()
        for rawLine in jhf.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = Array(rawLine.unicodeScalars)
            guard line.count >= 10 else { continue }
            let countText = String(String.UnicodeScalarView(line[5..<8])).trimmingCharacters(in: .whitespaces)
            guard let vertexPairs = Int(countText) else { continue }
            let data = Array(line[8...])
            let base = Double(UnicodeScalar("R").value)
            let lm = Double(data[0].value) - base
            let rm = Double(data[1].value) - base
            var strokes = [[SketchPoint]]()
            var current = [SketchPoint]()
            for pair in 1..<vertexPairs {
                let i = pair * 2
                guard i + 1 < data.count else { break }
                if data[i] == " ", data[i + 1] == "R" {
                    if current.count > 1 { strokes.append(current) }
                    current = []
                } else {
                    current.append(SketchPoint(
                        x: Double(data[i].value) - base,
                        y: Double(data[i + 1].value) - base
                    ))
                }
            }
            if current.count > 1 { strokes.append(current) }
            parsed.append(Glyph(leftMargin: lm, rightMargin: rm, strokes: strokes))
        }
        glyphs = parsed
    }

    /// Unknown characters render as the space glyph; a malformed font
    /// renders nothing rather than crashing (no force-unwraps, CLAUDE.md).
    public func glyph(for character: Character) -> Glyph {
        let fallback = glyphs.first ?? Glyph(leftMargin: -8, rightMargin: 8, strokes: [])
        guard let ascii = character.asciiValue else { return fallback }
        let index = Int(ascii) - 32
        guard glyphs.indices.contains(index) else { return fallback }
        return glyphs[index]
    }

    /// Lays out `text` at `size` (caps height in points), centered on
    /// `center`, returning strokes in writing order (left to right, each
    /// glyph's strokes in pen order — which is what makes the write-on
    /// entrance feel like writing). `rng` adds slight letter-spacing jitter.
    public func textStrokes(
        _ text: String,
        size: Double,
        centerX: Double,
        centerY: Double,
        rng: inout SketchRandom
    ) -> [[SketchPoint]] {
        let scale = size / Self.unitsPerEm
        var penX = 0.0
        var out = [[SketchPoint]]()
        for character in text {
            let g = glyph(for: character)
            for stroke in g.strokes {
                out.append(stroke.map { p in
                    SketchPoint(x: (penX + p.x - g.leftMargin) * scale, y: p.y * scale)
                })
            }
            penX += (g.rightMargin - g.leftMargin) + rng.nextSigned() * 0.8
        }
        guard !out.isEmpty else { return out }
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for stroke in out {
            for p in stroke {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        let ox = centerX - (minX + maxX) / 2
        let oy = centerY - (minY + maxY) / 2
        return out.map { $0.map { SketchPoint(x: $0.x + ox, y: $0.y + oy) } }
    }
}

// swiftlint:disable line_length
private let futuralJHF = #"""
12345  1JZ
12345  9MWRFRT RRYQZR[SZRY
12345  6JZNFNM RVFVM
12345 12H]SBLb RYBRb RLOZO RKUYU
12345 27H\PBP_ RTBT_ RYIWGTFPFMGKIKKLMMNOOUQWRXSYUYXWZT[P[MZKX
12345 32F^[FI[ RNFPHPJOLMMKMIKIIJGLFNFPGSHVHYG[F RWTUUTWTYV[X[ZZ[X[VYTWT
12345 35E_\O\N[MZMYNXPVUTXRZP[L[JZIYHWHUISJRQNRMSKSIRGPFNGMIMKNNPQUXWZY[[[\Z\Y
12345  8MWRHQGRFSGSIRKQL
12345 11KYVBTDRGPKOPOTPYR]T`Vb
12345 11KYNBPDRGTKUPUTTYR]P`Nb
12345  9JZRLRX RMOWU RWOMU
12345  6E_RIR[ RIR[R
12345  8NVSWRXQWRVSWSYQ[
12345  3E_IR[R
12345  6NVRVQWRXSWRV
12345  3G][BIb
12345 18H\QFNGLJKOKRLWNZQ[S[VZXWYRYOXJVGSFQF
12345  5H\NJPISFS[
12345 15H\LKLJMHNGPFTFVGWHXJXLWNUQK[Y[
12345 16H\MFXFRNUNWOXPYSYUXXVZS[P[MZLYKW
12345  7H\UFKTZT RUFU[
12345 18H\WFMFLOMNPMSMVNXPYSYUXXVZS[P[MZLYKW
12345 24H\XIWGTFRFOGMJLOLTMXOZR[S[VZXXYUYTXQVOSNRNOOMQLT
12345  6H\YFO[ RKFYF
12345 30H\PFMGLILKMMONSOVPXRYTYWXYWZT[P[MZLYKWKTLRNPQOUNWMXKXIWGTFPF
12345 24H\XMWPURRSQSNRLPKMKLLINGQFRFUGWIXMXRWWUZR[P[MZLX
12345 12NVROQPRQSPRO RRVQWRXSWRV
12345 14NVROQPRQSPRO RSWRXQWRVSWSYQ[
12345  4F^ZIJRZ[
12345  6E_IO[O RIU[U
12345  4F^JIZRJ[
12345 21I[LKLJMHNGPFTFVGWHXJXLWNVORQRT RRYQZR[SZRY
12345 56E`WNVLTKQKOLNMMPMSNUPVSVUUVS RQKOMNPNSOUPV RWKVSVUXVZV\T]Q]O\L[JYHWGTFQFNGLHJJILHOHRIUJWLYNZQ[T[WZYYZX RXKWSWUXV
12345  9I[RFJ[ RRFZ[ RMTWT
12345 24G\KFK[ RKFTFWGXHYJYLXNWOTP RKPTPWQXRYTYWXYWZT[K[
12345 19H]ZKYIWGUFQFOGMILKKNKSLVMXOZQ[U[WZYXZV
12345 16G\KFK[ RKFRFUGWIXKYNYSXVWXUZR[K[
12345 12H[LFL[ RLFYF RLPTP RL[Y[
12345  9HZLFL[ RLFYF RLPTP
12345 23H]ZKYIWGUFQFOGMILKKNKSLVMXOZQ[U[WZYXZVZS RUSZS
12345  9G]KFK[ RYFY[ RKPYP
12345  3NVRFR[
12345 11JZVFVVUYTZR[P[NZMYLVLT
12345  9G\KFK[ RYFKT RPOY[
12345  6HYLFL[ RL[X[
12345 12F^JFJ[ RJFR[ RZFR[ RZFZ[
12345  9G]KFK[ RKFY[ RYFY[
12345 22G]PFNGLIKKJNJSKVLXNZP[T[VZXXYVZSZNYKXIVGTFPF
12345 14G\KFK[ RKFTFWGXHYJYMXOWPTQKQ
12345 25G]PFNGLIKKJNJSKVLXNZP[T[VZXXYVZSZNYKXIVGTFPF RSWY]
12345 17G\KFK[ RKFTFWGXHYJYLXNWOTPKP RRPY[
12345 21H\YIWGTFPFMGKIKKLMMNOOUQWRXSYUYXWZT[P[MZKX
12345  6JZRFR[ RKFYF
12345 11G]KFKULXNZQ[S[VZXXYUYF
12345  6I[JFR[ RZFR[
12345 12F^HFM[ RRFM[ RRFW[ R\FW[
12345  6H\KFY[ RYFK[
12345  7I[JFRPR[ RZFRP
12345  9H\YFK[ RKFYF RK[Y[
12345 12KYOBOb RPBPb ROBVB RObVb
12345  3KYKFY^
12345 12KYTBTb RUBUb RNBUB RNbUb
12345  6JZRDJR RRDZR
12345  3I[Ib[b
12345  8NVSKQMQORPSORNQO
12345 18I\XMX[ RXPVNTMQMONMPLSLUMXOZQ[T[VZXX
12345 18H[LFL[ RLPNNPMSMUNWPXSXUWXUZS[P[NZLX
12345 15I[XPVNTMQMONMPLSLUMXOZQ[T[VZXX
12345 18I\XFX[ RXPVNTMQMONMPLSLUMXOZQ[T[VZXX
12345 18I[LSXSXQWOVNTMQMONMPLSLUMXOZQ[T[VZXX
12345  9MYWFUFSGRJR[ ROMVM
12345 23I\XMX]W`VaTbQbOa RXPVNTMQMONMPLSLUMXOZQ[T[VZXX
12345 11I\MFM[ RMQPNRMUMWNXQX[
12345  9NVQFRGSFREQF RRMR[
12345 12MWRFSGTFSERF RSMS^RaPbNb
12345  9IZMFM[ RWMMW RQSX[
12345  3NVRFR[
12345 19CaGMG[ RGQJNLMOMQNRQR[ RRQUNWMZM\N]Q][
12345 11I\MMM[ RMQPNRMUMWNXQX[
12345 18I\QMONMPLSLUMXOZQ[T[VZXXYUYSXPVNTMQM
12345 18H[LMLb RLPNNPMSMUNWPXSXUWXUZS[P[NZLX
12345 18I\XMXb RXPVNTMQMONMPLSLUMXOZQ[T[VZXX
12345  9KXOMO[ ROSPPRNTMWM
12345 18J[XPWNTMQMNNMPNRPSUTWUXWXXWZT[Q[NZMX
12345  9MYRFRWSZU[W[ ROMVM
12345 11I\MMMWNZP[S[UZXW RXMX[
12345  6JZLMR[ RXMR[
12345 12G]JMN[ RRMN[ RRMV[ RZMV[
12345  6J[MMX[ RXMM[
12345 10JZLMR[ RXMR[P_NaLbKb
12345  9J[XMM[ RMMXM RM[X[
12345 40KYTBRCQDPFPHQJRKSMSOQQ RRCQEQGRISJTLTNSPORSTTVTXSZR[Q]Q_Ra RQSSUSWRYQZP\P^Q`RaTb
12345  3NVRBRb
12345 40KYPBRCSDTFTHSJRKQMQOSQ RRCSESGRIQJPLPNQPURQTPVPXQZR[S]S_Ra RSSQUQWRYSZT\T^S`RaPb
12345 24F^IUISJPLONOPPTSVTXTZS[Q RISJQLPNPPQTTVUXUZT[Q[O
12345 35JZJFJ[K[KFLFL[M[MFNFN[O[OFPFP[Q[QFRFR[S[SFTFT[U[UFVFV[W[WFXFX[Y[YFZFZ[
"""#
// swiftlint:enable line_length
