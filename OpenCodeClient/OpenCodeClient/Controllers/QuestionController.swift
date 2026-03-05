import Foundation

enum QuestionController {
    static func fromPendingRequests(_ requests: [APIClient.QuestionRequest]) -> [PendingQuestion] {
        requests.map(toPendingQuestion)
    }

    static func parseAskedEvent(properties: [String: AnyCodable]) -> PendingQuestion? {
        let rawProps: [String: Any] = properties.mapValues { $0.value }
        let requestObject = (rawProps["request"] as? [String: Any]) ?? rawProps

        if JSONSerialization.isValidJSONObject(requestObject),
           let data = try? JSONSerialization.data(withJSONObject: requestObject),
           let decoded = try? JSONDecoder().decode(APIClient.QuestionRequest.self, from: data) {
            return toPendingQuestion(decoded)
        }

        func readString(_ key: String) -> String? {
            (requestObject[key] as? String) ?? (rawProps[key] as? String)
        }

        guard let sessionID = readString("sessionID") else { return nil }
        guard let questionID = readString("id") ?? readString("questionID") ?? readString("requestID") else { return nil }

        let questions: [PendingQuestionItem] = {
            if let questionObjects = requestObject["questions"] as? [[String: Any]] {
                return questionObjects.enumerated().map { parseQuestion($0.element, index: $0.offset) }
            }
            return []
        }()

        guard !questions.isEmpty else { return nil }

        let toolName: String? = {
            if let tool = requestObject["tool"] as? String { return tool }
            if let tool = requestObject["tool"] as? [String: Any] {
                return (tool["name"] as? String)
                    ?? (tool["tool"] as? String)
                    ?? (tool["id"] as? String)
                    ?? (tool["callID"] as? String)
            }
            return nil
        }()

        return PendingQuestion(
            sessionID: sessionID,
            questionID: questionID,
            questions: questions,
            tool: toolName
        )
    }

    static func applyResolvedEvent(properties: [String: AnyCodable], to questions: inout [PendingQuestion]) {
        let requestID = (properties["requestID"]?.value as? String) ?? (properties["id"]?.value as? String)
        guard let requestID else { return }

        if let sessionID = properties["sessionID"]?.value as? String {
            questions.removeAll { $0.sessionID == sessionID && $0.questionID == requestID }
            return
        }

        questions.removeAll { $0.questionID == requestID }
    }

    private static func toPendingQuestion(_ request: APIClient.QuestionRequest) -> PendingQuestion {
        let questions = request.questions.enumerated().map { index, q in
            PendingQuestionItem(
                id: "\(request.id)-\(index)",
                header: q.header,
                question: q.question,
                options: q.options.enumerated().map { optionIndex, option in
                    PendingQuestionOption(
                        id: "\(request.id)-\(index)-\(optionIndex)",
                        label: option.label,
                        description: option.description
                    )
                },
                multiple: q.multiple ?? false,
                custom: q.custom ?? true
            )
        }

        return PendingQuestion(
            sessionID: request.sessionID,
            questionID: request.id,
            questions: questions,
            tool: request.tool?.messageID ?? request.tool?.callID
        )
    }

    private static func parseQuestion(_ object: [String: Any], index: Int) -> PendingQuestionItem {
        let header = (object["header"] as? String) ?? "Question \(index + 1)"
        let question = (object["question"] as? String) ?? ""
        let multiple = (object["multiple"] as? Bool) ?? false
        let custom = (object["custom"] as? Bool) ?? true

        let options: [PendingQuestionOption] = {
            guard let optionObjects = object["options"] as? [[String: Any]] else { return [] }
            return optionObjects.enumerated().map { optionIndex, option in
                let label = (option["label"] as? String) ?? "Option \(optionIndex + 1)"
                let description = (option["description"] as? String) ?? ""
                return PendingQuestionOption(
                    id: "\(index)-\(optionIndex)-\(label)-\(description)",
                    label: label,
                    description: description
                )
            }
        }()

        return PendingQuestionItem(
            id: "fallback-\(index)",
            header: header,
            question: question,
            options: options,
            multiple: multiple,
            custom: custom
        )
    }
}
