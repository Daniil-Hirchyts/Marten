// Re-export Apple Intelligence services from MartenCore for backward compatibility
import MartenCore

@_exported import enum MartenCore.AppleIntelligenceTextAction
@_exported import enum MartenCore.AppleIntelligenceAvailability
@_exported import enum MartenCore.AppleIntelligenceTextTransformationError
@_exported import protocol MartenCore.AppleIntelligenceTextTransforming

public typealias AppleIntelligenceTextService = MartenCore.AppleIntelligenceTextService
