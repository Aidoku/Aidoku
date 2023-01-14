//
//  Promise.swift
//  Aidoku
//
//  Created by Skitty on 1/13/23.
//

import JavaScriptCore

@objc protocol PromiseExports: JSExport {
    func then(_ resolve: JSValue) -> Promise
    func `catch`(_ reject: JSValue) -> Promise
}

class Promise: NSObject, PromiseExports {

    var resultObservers: [JSValue] = []
    var errorObservers: [JSValue] = []

    var result: Any?
    var error: Any?

    var returnPromise: Promise?

    override init() {}

    @objc convenience init(executor: JSValue) {
        self.init()

        let resolve: @convention(block) (JSValue) -> Void = { value in // need strong self reference
            self.result = value
            self.update()
        }
        let reject: @convention(block) (JSValue) -> Void = { error in
            print("reject", error)
            self.error = error
            self.update()
        }

        executor.call(withArguments: [
            JSValue(object: resolve, in: executor.context)!,
            JSValue(object: reject, in: executor.context)!
        ])
    }

    convenience init(executor: @escaping (@escaping(Any) -> Void, @escaping(Any) -> Void) -> Void) {
        self.init()

        executor { [weak self] value in
            self?.result = value
            self?.update()
        } _: { [weak self] error in
            print("reject", error)
            self?.error = error
            self?.update()
        }
    }

    func update() {
        if let result = result {
            for resolution in resultObservers {
                let ret = resolution.call(withArguments: [result])
                if let returnPromise = returnPromise, let ret = ret {
                    returnPromise.resolve(ret)
                }
            }
            resultObservers = []
        } else if let error = error {
            if let returnPromise = returnPromise {
                returnPromise.error = error
                returnPromise.update()
            }

            for rejection in errorObservers {
                rejection.call(withArguments: [error])
            }
            errorObservers = []
        }
    }

    func then(_ block: JSValue) -> Promise {
//        let weakBlock = JSManagedValue(value: block, andOwner: self)
        returnPromise = Promise()
//        if let weakBlock = weakBlock {
            resultObservers.append(block)
//        }
        update()
        return returnPromise!
    }

    func `catch`(_ block: JSValue) -> Promise {
//        let weakBlock = JSManagedValue(value: block, andOwner: self)
        returnPromise = Promise()
//        if let weakBlock = weakBlock {
            errorObservers.append(block)
//        }
        update()
        return returnPromise!
    }

    func resolve(_ value: JSValue) {
        var newValue: Any? = value

        if let promise = value.toObject() as? Promise {
            if let result = promise.result {
                newValue = result
            } else {
                // todo
            }
        }

        result = newValue
        update()
    }

    func reject(_ value: JSValue) {
        if let promise = value.toObject() as? Promise {
            if let childError = promise.error {
                error = childError
            }
        } else {
            error = value
        }

        update()
    }

    func fail(_ errorString: String) {
        error = errorString
        update()
    }
}
