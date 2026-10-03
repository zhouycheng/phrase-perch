import Foundation
import Observation

struct ConfigurationIssue: Equatable {
    enum Operation: String {
        case load = "读取失败"
        case save = "保存失败"
        case recovery = "恢复失败"
        case importFile = "导入失败"
        case exportFile = "导出失败"
    }
    let operation: Operation
    let message: String
}
