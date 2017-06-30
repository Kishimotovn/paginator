import URI
import HTTP
import Core
import Vapor
import Fluent

public class Paginator<EntityType: Entity> {
    public var currentPage: Int
    public var perPage: Int

    public var total: Int?

    public var baseURI: URI
    public var uriQueries: Node?

    public var paginatorName: String
    public var pageName: String
    public var dataKey: String

    public var totalPages: Int? {
        guard let total = total else {
            return nil
        }

        var pages = total / perPage
        if total % perPage != 0 {
            pages += 1
        }

        return pages
    }

    public var previousPage: String? {
        let previous = currentPage - 1
        guard previous >= 1 else { return nil }

        return PaginatorHelper.buildPath(
            baseURI: baseURI.path,
            page: previous,
            count: perPage,
            uriQueries: uriQueries,
            pageName: pageName
        )
    }

    public var nextPage: String? {
        guard let totalPages = totalPages else { return nil }
        let next = currentPage + 1
        guard next <= totalPages else { return nil }

        return PaginatorHelper.buildPath(
            baseURI: baseURI.path,
            page: next,
            count: perPage,
            uriQueries: uriQueries,
            pageName: pageName
        )
    }

    public var data: [EntityType]?

    var query: Query<EntityType>
    var transform: (([EntityType]) throws -> Node)?

    init(
        query: Query<EntityType>,
        currentPage: Int = 1,
        perPage: Int,
        paginatorName: String,
        pageName: String,
        dataKey: String,
        transform: (([EntityType]) throws -> Node)?,
        request: Request
    ) throws {
        self.query = query
        self.currentPage = currentPage
        self.perPage = perPage
        self.paginatorName = paginatorName
        self.pageName = pageName
        self.dataKey = dataKey
        self.transform = transform

        baseURI = request.uri
        uriQueries = request.query

        self.data = try extractEntityData()
    }

    public init(
        _ entities: [EntityType],
        page currentPage: Int = 1,
        perPage: Int,
        paginatorName: String = "paginator",
        pageName: String = "page",
        dataKey: String = "data",
        request: Request
    ) throws {
        query = try EntityType.query()
        self.currentPage = currentPage
        self.perPage = perPage
        self.paginatorName = paginatorName
        self.pageName = pageName
        self.dataKey = dataKey

        baseURI = request.uri
        uriQueries = request.query
        total = entities.count
        data = extractSequenceData(from: entities)
        transform = nil
    }
}

extension Paginator {
    func extractEntityData() throws -> [EntityType] {
        //FIXME(Brett): Better caching system
        total = try total ?? query.run().count

        if let page = uriQueries?[pageName]?.int {
            currentPage = page
        }

        if let count = uriQueries?["count"]?.int, count < perPage {
            perPage = count
        }

        let offset = (currentPage - 1) * perPage
        let limit = Limit(count: perPage, offset: offset)
        query.limit = limit

        return try query.run()
    }

    func extractSequenceData(from data: [EntityType]?) -> [EntityType] {
        guard let sequenceData = data else {
            return []
        }

        var pageData = sequenceData

        if pageData.count > 0 {
            if let page = uriQueries?[pageName]?.int {
                currentPage = page
            }

            if let count = uriQueries?["count"]?.int, count < perPage {
                perPage = count
            }

            var position = (((currentPage - 1) * perPage) + perPage) - 1

            let offset = perPage * (currentPage - 1)

            if offset > pageData.count {
                return []
            }

            if position >= pageData.count {
                position = pageData.count - 1
            }

            pageData = Array(pageData[offset...position])
        }

        return pageData
    }
}

extension Paginator: NodeRepresentable {
    public func makeNode(context: Context) throws -> Node {
        return try Node(node: [
            "meta": Node(node: [
                paginatorName: Node(node: [
                    "total": total,
                    "per_page": perPage,
                    "current_page": currentPage,
                    "total_pages": totalPages,
                    "queries": uriQueries,
                    "links": Node(node: [
                        "previous": previousPage,
                        "next": nextPage
                    ]),
                ])
            ]),

            dataKey: transform?(data ?? []) ?? data?.makeNode(context: context)
        ])
    }
}

extension Node {
    func formEncode() -> String? {
        guard case .object(let dict) = self else {
            return nil
        }

        return dict.map {
            [$0.key, $0.value.string ?? ""].joined(separator: "=")
        }.joined(separator: "&")
    }
}

extension Request {
    public func addingValues(_ queries: [String : String]) throws -> Request {
        var newQueries = query?.nodeObject ?? [:]

        queries.forEach {
            newQueries[$0.key] = $0.value.makeNode()
        }

        query = try newQueries.makeNode()
        return self
    }
}
