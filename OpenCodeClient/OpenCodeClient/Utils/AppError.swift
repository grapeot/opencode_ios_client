//
//  AppError.swift
//  OpenCodeClient
//

import Foundation

enum AppError: Error, Equatable {
    case connectionFailed(String)
    case serverError(String)
    case invalidResponse
    case unauthorized
    case sessionNotFound
    case fileNotFound(String)
    case operationFailed(String)
    case unknown(String)
    
    var localizedDescription: String {
        switch self {
        case .connectionFailed(let detail):
            return L10n.errorMessage(.errorConnectionFailed, detail)
        case .serverError(let detail):
            return L10n.errorMessage(.errorServerError, detail)
        case .invalidResponse:
            return L10n.t(.errorInvalidResponse)
        case .unauthorized:
            return L10n.t(.errorUnauthorized)
        case .sessionNotFound:
            return L10n.t(.errorSessionNotFound)
        case .fileNotFound(let path):
            return L10n.errorMessage(.errorFileNotFound, path)
        case .operationFailed(let detail):
            return L10n.errorMessage(.errorOperationFailed, detail)
        case .unknown(let detail):
            return L10n.errorMessage(.errorUnknown, detail)
        }
    }
    
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        
        let errorString = error.localizedDescription
        
        if errorString.contains("401") || errorString.contains("Unauthorized") {
            return .unauthorized
        }
        
        if errorString.contains("invalid URL") || errorString.contains("Invalid URL") {
            return .operationFailed(L10n.t(.errorInvalidBaseURL))
        }
        
        if errorString.contains("HTTP") {
            return .serverError(errorString)
        }
        
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .connectionFailed(errorString)
        }
        
        return .unknown(errorString)
    }
}

extension AppError {
    var isConnectionError: Bool {
        if case .connectionFailed = self { return true }
        return false
    }
    
    var isRecoverable: Bool {
        switch self {
        case .connectionFailed, .unauthorized, .serverError:
            return true
        case .invalidResponse, .sessionNotFound, .fileNotFound, .operationFailed, .unknown:
            return false
        }
    }
}
