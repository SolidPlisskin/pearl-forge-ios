import Foundation

/// A paper found on PubMed.
struct PubMedPaper: Codable, Equatable {
    var pmid: String
    var title = ""
    var journal = ""
    var year = ""
    var authors: [String] = []
    var abstract = ""
    var doi: String?

    var url: String { "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/" }

    /// "Smith J, Lee K, et al."
    var authorLine: String {
        authors.count > 3 ? authors.prefix(3).joined(separator: ", ") + ", et al." : authors.joined(separator: ", ")
    }
}

/// Searches PubMed through the National Library of Medicine's free E-utilities
/// service. No key is needed.
enum PubMedClient {
    private static let base = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils")!

    /// The most relevant papers for a PubMed query, with their abstracts.
    static func search(_ query: String, maxResults: Int = 6) async throws -> [PubMedPaper] {
        let ids = try await searchIDs(query, maxResults: max(1, min(maxResults, 10)))
        guard !ids.isEmpty else { return [] }
        return try await fetch(ids)
    }

    private static func searchIDs(_ query: String, maxResults: Int) async throws -> [String] {
        var components = URLComponents(url: base.appendingPathComponent("esearch.fcgi"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "retmax", value: String(maxResults)),
            URLQueryItem(name: "sort", value: "relevance"),
            URLQueryItem(name: "retmode", value: "json"),
            URLQueryItem(name: "tool", value: "PearlForge"),
        ]
        let data = try await PipelineHTTP.send(URLRequest(url: components.url!, timeoutInterval: 60),
                                               failure: "PubMed search failed")
        struct Response: Decodable {
            struct Result: Decodable { let idlist: [String]? }
            let esearchresult: Result?
        }
        return try JSONDecoder().decode(Response.self, from: data).esearchresult?.idlist ?? []
    }

    private static func fetch(_ ids: [String]) async throws -> [PubMedPaper] {
        var components = URLComponents(url: base.appendingPathComponent("efetch.fcgi"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
            URLQueryItem(name: "rettype", value: "abstract"),
            URLQueryItem(name: "retmode", value: "xml"),
            URLQueryItem(name: "tool", value: "PearlForge"),
        ]
        let data = try await PipelineHTTP.send(URLRequest(url: components.url!, timeoutInterval: 60),
                                               failure: "PubMed lookup failed")
        let papers = PubMedXMLParser.parse(data)
        // Keep PubMed's relevance order.
        return ids.compactMap { id in papers.first { $0.pmid == id } }
    }
}

/// Reads the parts of PubMed's article XML that Pearl Forge shows.
final class PubMedXMLParser: NSObject, XMLParserDelegate {
    private var papers: [PubMedPaper] = []
    private var current: PubMedPaper?
    private var path: [String] = []
    /// The text inside each open element; inline markup like <i> inside an
    /// abstract is folded into its parent.
    private var texts: [String] = []
    private var lastName = ""
    private var initials = ""
    private var articleIDType = ""

    static func parse(_ data: Data) -> [PubMedPaper] {
        let delegate = PubMedXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.papers
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        path.append(element)
        texts.append("")
        switch element {
        case "PubmedArticle": current = PubMedPaper(pmid: "")
        case "Author": lastName = ""; initials = ""
        case "ArticleId": articleIDType = attributes["IdType"] ?? ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !texts.isEmpty { texts[texts.count - 1] += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let raw = texts.removeLast()
        if !texts.isEmpty { texts[texts.count - 1] += raw }
        defer { path.removeLast() }
        guard current != nil else { return }
        let value = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let parent = path.dropLast().last ?? ""
        switch element {
        case "PMID" where parent == "MedlineCitation" && current!.pmid.isEmpty:
            current!.pmid = value
        case "ArticleTitle":
            current!.title = value
        case "Title" where parent == "Journal":
            current!.journal = value
        case "Year" where parent == "PubDate":
            current!.year = value
        case "MedlineDate" where parent == "PubDate" && current!.year.isEmpty:
            current!.year = String(value.prefix(4))
        case "AbstractText":
            current!.abstract += (current!.abstract.isEmpty ? "" : " ") + value
        case "LastName": lastName = value
        case "Initials": initials = value
        case "Author" where !lastName.isEmpty:
            current!.authors.append(initials.isEmpty ? lastName : "\(lastName) \(initials)")
        case "ArticleId" where articleIDType == "doi" && current!.doi == nil:
            current!.doi = value
        case "PubmedArticle":
            if !current!.pmid.isEmpty { papers.append(current!) }
            current = nil
        default:
            break
        }
    }
}
