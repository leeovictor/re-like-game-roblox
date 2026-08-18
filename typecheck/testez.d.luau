declare function describe(name: string, callback: () -> ()): ()
declare function it(name: string, callback: () -> ()): ()
declare function beforeEach(callback: () -> ()): ()
declare function afterEach(callback: () -> ()): ()
declare function expect(value: any): any
