// Pearl Forge's refinement instructions, carried over word-for-word from the
// working Pinokio build (pearl-ui/pipeline.py: SYSTEM_BASE and
// MODE_INSTRUCTIONS). The wording is the product — change it only on purpose.

import Foundation

/// How much refinement Claude applies. Raw values match the Pinokio build's
/// mode keys so saved recordings stay readable across both versions.
enum RefinementMode: String, CaseIterable, Identifiable, Codable {
    case clean
    case tighten
    case summarize
    /// Typed text spoken exactly as written (or only translated), not polished.
    case asWritten = "aswritten"

    var id: String { rawValue }

    /// The modes that polish, offered for recordings and new pearls.
    static let polishingModes: [RefinementMode] = [.clean, .tighten, .summarize]

    var title: String {
        switch self {
        case .clean: return "Clean"
        case .tighten: return "Tighten"
        case .summarize: return "Summarize"
        case .asWritten: return "As written"
        }
    }

    /// The short description shown next to the mode name.
    var subtitle: String {
        switch self {
        case .clean: return "light tidy-up, keeps almost everything"
        case .tighten: return "reorganise and de-clutter, keep the nuance"
        case .summarize: return "condensed to the core, still your view"
        case .asWritten: return "your exact words, not polished"
        }
    }

    /// The subtitle as a sentence: "Light tidy-up, keeps almost everything."
    var subtitleSentence: String {
        subtitle.prefix(1).uppercased() + subtitle.dropFirst() + "."
    }

    var instruction: String {
        switch self {
        case .clean: return RefinementPrompts.clean
        case .tighten: return RefinementPrompts.tighten
        case .summarize: return RefinementPrompts.summarize
        case .asWritten: return ""
        }
    }
}

enum RefinementPrompts {
    /// The full system prompt for one refinement request. Without notes it is
    /// exactly the Pinokio build's prompt; your notes for a pearl are added
    /// after it.
    static func system(for mode: RefinementMode, notes: String? = nil) -> String {
        let prompt = systemBase + "\n\n" + mode.instruction
        guard let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
            return prompt
        }
        return prompt + "\n\n" + speakerRequest(notes)
    }

    /// What you asked to be different for one pearl. Not part of the Pinokio
    /// prompts; added only when you write a request.
    static func speakerRequest(_ notes: String) -> String {
        """
        SPEAKER'S REQUEST FOR THIS VERSION:
        \(notes)

        Apply this request on top of the mode above. Everything else in the rules above still holds; depart from a rule only where the request explicitly asks you to.
        """
    }

    static let systemBase = """
    You are Pearl Forge. You are given the verbatim transcript of a voice note in which the speaker is thinking out loud. Your job is to improve HOW CLEARLY the thought is expressed, WITHOUT changing the thought itself. The result will be read back aloud in the speaker's own voice, in the first person, so it must sound like the speaker on an articulate day — not like a different narrator.

    These rules are absolute. Never break them, in any mode:
    - Never increase certainty. If the speaker hedges ("maybe", "I think", "I'm not sure", "probably", "it seems"), keep the hedge. A possibility must never become a flat claim.
    - Never remove qualifications, caveats, conditions, or the sense that the speaker is exploring rather than concluding.
    - Never add facts, opinions, conclusions, analogies, or examples the speaker did not say. Do not insert your own analysis or your own conclusions.
    - Keep the speaker's personality: their humour, their analogies, their unusual associations, and digressions that genuinely add to the idea. Do not flatten the writing into generic or corporate prose.
    - Keep it first person and in the speaker's own words as much as possible. Improve the expression; do not replace the voice.

    Output ONLY the refined text. No preamble, no title, no notes, no quotation marks wrapping the whole thing, no explanation of what you changed.
    """

    static let clean = """
    MODE: Clean.
    Make only light, mechanical edits — the way a careful transcriptionist tidies up dictation. Remove filler words ("um", "uh", "like", "you know"), false starts, stutters, and word-for-word repetition. Fix obvious grammar and broken run-on sentences. KEEP the original order of ideas, the conversational tone, and nearly all of the substance. Do NOT reorganise, condense, or rewrite in a more polished register.
    """

    static let tighten = """
    MODE: Tighten.
    Improve how the explanation is built. Combine sentences that make the same point, move closely related points next to each other, fix awkward ordering, and smooth the transitions so the argument flows. KEEP every important nuance and qualification, and keep the speaker's distinctive phrasing and the digressions that add value. Do not shorten by dropping ideas — only by removing waste and repetition.
    """

    static let summarize = """
    MODE: Summarize.
    Produce a genuinely condensed version, in the speaker's first-person voice, containing the central argument, the major supporting points, the important qualifications, and the final conclusions. This mode deliberately sacrifices detail — but it must still represent the speaker's ACTUAL position and their uncertainty, never a more confident, tidier, or more generic version of it.
    """
}
