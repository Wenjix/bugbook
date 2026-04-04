import Foundation

public struct SchemaValidator {

    /// Validate property values against a database schema.
    /// Returns an empty array if all values are valid.
    public static func validate(properties: [String: PropertyValue], schema: DatabaseSchema,
                                requireTitle: Bool = false) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Check title is present if required (for creates)
        if requireTitle {
            if let titleProp = schema.titleProperty {
                if let val = properties[titleProp.id] {
                    switch val {
                    case .text(let s) where s.isEmpty:
                        errors.append(ValidationError(propertyId: titleProp.id, message: "Title cannot be empty"))
                    case .empty:
                        errors.append(ValidationError(propertyId: titleProp.id, message: "Title cannot be empty"))
                    default:
                        break
                    }
                } else {
                    errors.append(ValidationError(propertyId: titleProp.id, message: "Title property is required"))
                }
            }
        }

        let propMap = Dictionary(uniqueKeysWithValues: schema.properties.map { ($0.id, $0) })

        for (propId, value) in properties {
            // Empty values are always allowed (clearing a field)
            if case .empty = value { continue }

            guard let propDef = propMap[propId] else {
                errors.append(ValidationError(propertyId: propId, message: "Property does not exist in schema"))
                continue
            }

            if let error = validateType(value: value, definition: propDef) {
                errors.append(error)
            }
        }

        return errors
    }

    private static func validateType(value: PropertyValue, definition: PropertyDefinition) -> ValidationError? {
        switch definition.type {
        case .title, .text:
            if case .text = value { return nil }
            return ValidationError(propertyId: definition.id, message: "Expected text value for \(definition.type) property")

        case .number:
            if case .number = value { return nil }
            return ValidationError(propertyId: definition.id, message: "Expected number value")

        case .select:
            guard case .select(let optionId) = value else {
                return ValidationError(propertyId: definition.id, message: "Expected select value")
            }
            if let options = definition.config?.options {
                if !options.contains(where: { $0.id == optionId }) {
                    return ValidationError(propertyId: definition.id, message: "Invalid select option '\(optionId)'")
                }
            }
            return nil

        case .multiSelect:
            guard case .multiSelect(let optionIds) = value else {
                return ValidationError(propertyId: definition.id, message: "Expected multi_select value")
            }
            if let options = definition.config?.options {
                let validIds = Set(options.map(\.id))
                for optId in optionIds {
                    if !validIds.contains(optId) {
                        return ValidationError(propertyId: definition.id, message: "Invalid multi_select option '\(optId)'")
                    }
                }
            }
            return nil

        case .date:
            if case .date = value { return nil }
            return ValidationError(propertyId: definition.id, message: "Expected date value")

        case .checkbox:
            if case .checkbox = value { return nil }
            return ValidationError(propertyId: definition.id, message: "Expected checkbox value")

        case .url:
            if case .url = value { return nil }
            return ValidationError(propertyId: definition.id, message: "Expected url value")

        case .email:
            if case .email = value { return nil }
            return ValidationError(propertyId: definition.id, message: "Expected email value")

        case .relation:
            if case .relation = value { return nil }
            if case .relationMany = value { return nil }
            return ValidationError(propertyId: definition.id, message: "Expected relation value")

        case .formula:
            // Formula values are computed, not stored — any persisted value is acceptable.
            return nil
        }
    }
}
