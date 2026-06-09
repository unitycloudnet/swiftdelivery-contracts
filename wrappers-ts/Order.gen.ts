// AUTO-GENERATED, do not edit
// It's a TypeScript wrapper for a Order contract in Tolk.
/* eslint-disable */

import * as c from '@ton/core';
import { beginCell, ContractProvider, Sender, SendMode } from '@ton/core';

// ————————————————————————————————————————————
//   predefined types and functions
//

type StoreCallback<T> = (obj: T, b: c.Builder) => void
type LoadCallback<T> = (s: c.Slice) => T

export type CellRef<T> = {
    ref: T
}

function makeCellFrom<T>(self: T, storeFn_T: StoreCallback<T>): c.Cell {
    let b = beginCell();
    storeFn_T(self, b);
    return b.endCell();
}

function loadAndCheckPrefix32(s: c.Slice, expected: number, structName: string): void {
    let prefix = s.loadUint(32);
    if (prefix !== expected) {
        throw new Error(`Incorrect prefix for '${structName}': expected 0x${expected.toString(16).padStart(8, '0')}, got 0x${prefix.toString(16).padStart(8, '0')}`);
    }
}

function lookupPrefix(s: c.Slice, expected: number, prefixLen: number): boolean {
    return s.remainingBits >= prefixLen && s.preloadUint(prefixLen) === expected;
}

function throwNonePrefixMatch(fieldPath: string): never {
    throw new Error(`Incorrect prefix for '${fieldPath}': none of variants matched`);
}

function storeCellRef<T>(cell: CellRef<T>, b: c.Builder, storeFn_T: StoreCallback<T>): void {
    let b_ref = c.beginCell();
    storeFn_T(cell.ref, b_ref);
    b.storeRef(b_ref.endCell());
}

function loadCellRef<T>(s: c.Slice, loadFn_T: LoadCallback<T>): CellRef<T> {
    let s_ref = s.loadRef().beginParse();
    return { ref: loadFn_T(s_ref) };
}

function storeTolkNullable<T>(v: T | null, b: c.Builder, storeFn_T: StoreCallback<T>): void {
    if (v === null) {
        b.storeUint(0, 1);
    } else {
        b.storeUint(1, 1);
        storeFn_T(v, b);
    }
}

// ————————————————————————————————————————————
//   parse get methods result from a TVM stack
//

class StackReader {
    constructor(private tuple: c.TupleItem[]) {
    }

    static fromGetMethod(expectedN: number, getMethodResult: { stack: c.TupleReader }): StackReader {
        let tuple = [] as c.TupleItem[];
        while (getMethodResult.stack.remaining) {
            tuple.push(getMethodResult.stack.pop());
        }
        if (tuple.length !== expectedN) {
            throw new Error(`expected ${expectedN} stack width, got ${tuple.length}`);
        }
        return new StackReader(tuple);
    }

    private popExpecting<ItemT>(itemType: string): ItemT {
        const item = this.tuple.shift();
        if (item?.type === itemType) {
            return item as ItemT;
        }
        throw new Error(`not '${itemType}' on a stack`);
    }

    private popCellLike(): c.Cell {
        const item = this.tuple.shift();
        if (item && (item.type === 'cell' || item.type === 'slice' || item.type === 'builder')) {
            return item.cell;
        }
        throw new Error(`not cell/slice on a stack`);
    }

    readBigInt(): bigint {
        return this.popExpecting<c.TupleItemInt>('int').value;
    }

    readBoolean(): boolean {
        return this.popExpecting<c.TupleItemInt>('int').value !== 0n;
    }

    readCell(): c.Cell {
        return this.popCellLike();
    }

    readSlice(): c.Slice {
        return this.popCellLike().beginParse();
    }

    readNullable<T>(readFn_T: (r: StackReader) => T): T | null {
        if (this.tuple[0].type === 'null') {
            this.tuple.shift();
            return null;
        }
        return readFn_T(this);
    }

    readCellRef<T>(loadFn_T: LoadCallback<T>): CellRef<T> {
        return { ref: loadFn_T(this.readCell().beginParse()) };
    }
}

// ————————————————————————————————————————————
//   auto-generated serializers to/from cells
//

type coins = bigint

type uint32 = bigint
type uint64 = bigint

/**
 > enum OrderStatus { 5 variants }
 */
export type OrderStatus = bigint

export const OrderStatus = {
    Open: 0n,
    Accepted: 1n,
    Completed: 2n,
    Cancelled: 3n,
    Expired: 4n,

    fromSlice(s: c.Slice): OrderStatus {
        return s.loadUintBig(8);
    },
    store(self: OrderStatus, b: c.Builder): void {
        b.storeUint(self, 8);
    },
    toCell(self: OrderStatus): c.Cell {
        return makeCellFrom<OrderStatus>(self, OrderStatus.store);
    }
}

/**
 > struct OrderExtra {
 >     owner: address
 >     senderContact: cell
 >     courierContact: cell
 > }
 */
export interface OrderExtra {
    readonly $: 'OrderExtra'
    owner: c.Address
    senderContact: c.Cell
    courierContact: c.Cell
}

export const OrderExtra = {
    create(args: {
        owner: c.Address
        senderContact: c.Cell
        courierContact: c.Cell
    }): OrderExtra {
        return {
            $: 'OrderExtra',
            ...args
        }
    },
    fromSlice(s: c.Slice): OrderExtra {
        return {
            $: 'OrderExtra',
            owner: s.loadAddress(),
            senderContact: s.loadRef(),
            courierContact: s.loadRef(),
        }
    },
    store(self: OrderExtra, b: c.Builder): void {
        b.storeAddress(self.owner);
        b.storeRef(self.senderContact);
        b.storeRef(self.courierContact);
    },
    toCell(self: OrderExtra): c.Cell {
        return makeCellFrom<OrderExtra>(self, OrderExtra.store);
    }
}

/**
 > struct OrderStorage {
 >     sender: address
 >     courier: address?
 >     description: cell
 >     area: cell
 >     origin: cell
 >     reward: coins
 >     status: OrderStatus
 >     nonce: uint64
 >     createdAt: uint32
 >     acceptedAt: uint32
 >     extra: Cell<OrderExtra>
 > }
 */
export interface OrderStorage {
    readonly $: 'OrderStorage'
    sender: c.Address
    courier: c.Address | null
    description: c.Cell
    area: c.Cell
    origin: c.Cell
    reward: coins
    status: OrderStatus
    nonce: uint64
    createdAt: uint32
    acceptedAt: uint32
    extra: CellRef<OrderExtra>
}

export const OrderStorage = {
    create(args: {
        sender: c.Address
        courier: c.Address | null
        description: c.Cell
        area: c.Cell
        origin: c.Cell
        reward: coins
        status: OrderStatus
        nonce: uint64
        createdAt: uint32
        acceptedAt: uint32
        extra: CellRef<OrderExtra>
    }): OrderStorage {
        return {
            $: 'OrderStorage',
            ...args
        }
    },
    fromSlice(s: c.Slice): OrderStorage {
        return {
            $: 'OrderStorage',
            sender: s.loadAddress(),
            courier: s.loadMaybeAddress(),
            description: s.loadRef(),
            area: s.loadRef(),
            origin: s.loadRef(),
            reward: s.loadCoins(),
            status: OrderStatus.fromSlice(s),
            nonce: s.loadUintBig(64),
            createdAt: s.loadUintBig(32),
            acceptedAt: s.loadUintBig(32),
            extra: loadCellRef<OrderExtra>(s, OrderExtra.fromSlice),
        }
    },
    store(self: OrderStorage, b: c.Builder): void {
        b.storeAddress(self.sender);
        b.storeAddress(self.courier);
        b.storeRef(self.description);
        b.storeRef(self.area);
        b.storeRef(self.origin);
        b.storeCoins(self.reward);
        OrderStatus.store(self.status, b);
        b.storeUint(self.nonce, 64);
        b.storeUint(self.createdAt, 32);
        b.storeUint(self.acceptedAt, 32);
        storeCellRef<OrderExtra>(self.extra, b, OrderExtra.store);
    },
    toCell(self: OrderStorage): c.Cell {
        return makeCellFrom<OrderStorage>(self, OrderStorage.store);
    }
}

/**
 > struct (0xa00a0001) AcceptOrder {
 >     courierContact: cell
 > }
 */
export interface AcceptOrder {
    readonly $: 'AcceptOrder'
    courierContact: c.Cell
}

export const AcceptOrder = {
    PREFIX: 0xa00a0001,

    create(args: {
        courierContact: c.Cell
    }): AcceptOrder {
        return {
            $: 'AcceptOrder',
            ...args
        }
    },
    fromSlice(s: c.Slice): AcceptOrder {
        loadAndCheckPrefix32(s, 0xa00a0001, 'AcceptOrder');
        return {
            $: 'AcceptOrder',
            courierContact: s.loadRef(),
        }
    },
    store(self: AcceptOrder, b: c.Builder): void {
        b.storeUint(0xa00a0001, 32);
        b.storeRef(self.courierContact);
    },
    toCell(self: AcceptOrder): c.Cell {
        return makeCellFrom<AcceptOrder>(self, AcceptOrder.store);
    }
}

/**
 > struct (0xa00a0002) ConfirmDelivery {
 > }
 */
export interface ConfirmDelivery {
    readonly $: 'ConfirmDelivery'
}

export const ConfirmDelivery = {
    PREFIX: 0xa00a0002,

    create(): ConfirmDelivery {
        return {
            $: 'ConfirmDelivery',
        }
    },
    fromSlice(s: c.Slice): ConfirmDelivery {
        loadAndCheckPrefix32(s, 0xa00a0002, 'ConfirmDelivery');
        return {
            $: 'ConfirmDelivery',
        }
    },
    store(self: ConfirmDelivery, b: c.Builder): void {
        b.storeUint(0xa00a0002, 32);
    },
    toCell(self: ConfirmDelivery): c.Cell {
        return makeCellFrom<ConfirmDelivery>(self, ConfirmDelivery.store);
    }
}

/**
 > struct (0xa00a0003) CancelOrder {
 > }
 */
export interface CancelOrder {
    readonly $: 'CancelOrder'
}

export const CancelOrder = {
    PREFIX: 0xa00a0003,

    create(): CancelOrder {
        return {
            $: 'CancelOrder',
        }
    },
    fromSlice(s: c.Slice): CancelOrder {
        loadAndCheckPrefix32(s, 0xa00a0003, 'CancelOrder');
        return {
            $: 'CancelOrder',
        }
    },
    store(self: CancelOrder, b: c.Builder): void {
        b.storeUint(0xa00a0003, 32);
    },
    toCell(self: CancelOrder): c.Cell {
        return makeCellFrom<CancelOrder>(self, CancelOrder.store);
    }
}

/**
 > struct (0xa00a0004) ClaimExpired {
 > }
 */
export interface ClaimExpired {
    readonly $: 'ClaimExpired'
}

export const ClaimExpired = {
    PREFIX: 0xa00a0004,

    create(): ClaimExpired {
        return {
            $: 'ClaimExpired',
        }
    },
    fromSlice(s: c.Slice): ClaimExpired {
        loadAndCheckPrefix32(s, 0xa00a0004, 'ClaimExpired');
        return {
            $: 'ClaimExpired',
        }
    },
    store(self: ClaimExpired, b: c.Builder): void {
        b.storeUint(0xa00a0004, 32);
    },
    toCell(self: ClaimExpired): c.Cell {
        return makeCellFrom<ClaimExpired>(self, ClaimExpired.store);
    }
}

/**
 > struct (0xa00a0005) CourierRelease {
 > }
 */
export interface CourierRelease {
    readonly $: 'CourierRelease'
}

export const CourierRelease = {
    PREFIX: 0xa00a0005,

    create(): CourierRelease {
        return {
            $: 'CourierRelease',
        }
    },
    fromSlice(s: c.Slice): CourierRelease {
        loadAndCheckPrefix32(s, 0xa00a0005, 'CourierRelease');
        return {
            $: 'CourierRelease',
        }
    },
    store(self: CourierRelease, b: c.Builder): void {
        b.storeUint(0xa00a0005, 32);
    },
    toCell(self: CourierRelease): c.Cell {
        return makeCellFrom<CourierRelease>(self, CourierRelease.store);
    }
}

// ————————————————————————————————————————————
//    class Order
//

interface ExtraSendOptions {
    bounce?: boolean                    // default: false
    sendMode?: SendMode                 // default: SendMode.PAY_GAS_SEPARATELY
    extraCurrencies?: c.ExtraCurrency   // default: empty dict
}

interface DeployedAddrOptions {
    workchain?: number                  // default: 0 (basechain)
    toShard?: { fixedPrefixLength: number; closeTo: c.Address }
    overrideContractCode?: c.Cell
}

function calculateDeployedAddress(code: c.Cell, data: c.Cell, options: DeployedAddrOptions): c.Address {
    const stateInitCell = beginCell().store(c.storeStateInit({
        code,
        data,
        splitDepth: options.toShard?.fixedPrefixLength,
        special: null,
        libraries: null,
    })).endCell();

    let addrHash = stateInitCell.hash();
    if (options.toShard) {
        const shardDepth = options.toShard.fixedPrefixLength;
        addrHash = beginCell()
            .storeBits(new c.BitString(options.toShard.closeTo.hash, 0, shardDepth))
            .storeBits(new c.BitString(stateInitCell.hash(), shardDepth, 256 - shardDepth))
            .endCell()
            .beginParse().loadBuffer(32);
    }

    return new c.Address(options.workchain ?? 0, addrHash);
}

export class Order implements c.Contract {
    static CodeCell = c.Cell.fromBase64('te6ccgECDQEAAoQAART/APSkE/S88sgLAQIBYgIDBPjQ+JGRMOAg7UTQ+kj6UNTU1PoA0wchwgTyRdZf0x/XTArXLCUAUAAMjkMxNzny0GT4l4IQBfXhAL7y4Gf4kvgjCND6SNTUMdEH10wByPpSF8wWzMkGyPpSFfpUE8zMzAH6As+EBhPOyx/Mye1U4NcsJQBQABTjAonXJ+MCBAUGBwIBWAsMANAwOgHAAfLgZPiSJ8cF8uBlJsj6UlJg+lQVzBPMzCH6As+EChLOFcsfI88Uye1UyM+FCPpSUAP6AnDPC2rJcfsAyM+FCBL6UnDPC27JgED7AND6SNQx1DHRyM+FCPpScM8LbsmBAKD7AAAIoAoABADEMDoBwAHy4GT4IymBDhCgvPLgaPiSJ8cF8uBlJsj6Uhb6VBTMEszMIfoCz4QSEs4Uyx8izxTJ7VTIz4UI+lJY+gJwzwtqyYBA+wDQ+kjUMdQx0cjPhQj6UnDPC27JgQCg+wAC8onXJ45gMDoB8tBk+JInxwXy4GX4l4IQEeGjAL7y4GcmyPpSFvpUFMwSzMwh+gLPhA4SzhTLHyLPFMntVMjPhQj6Ulj6AnDPC2rJcfsA0PpI1DHUMdHIz4UI+lJwzwtuyYEAoPsA4NcsJQBQACwx4wJfCoQPAccA8vQICQAIoAoAAwGsOgHAAfLgZPiSFscF8uBm+CMIgQ4QoBi78uBp+JeCEAvrwgC+8uBnbQbQ+kjU1DHRiALI+lLMzMkFyPpSFvpUEszME8xQA/oCz4QCzs+QAAAAAszJ7VQKAAAALbjQrtRND6SDH6UDH6ADHXCwcgwgTyRYADu5g37UTQ+kj6UNTU1PoA0wchwgTyRdM/0x/TH9dMg=');

    static Errors = {
        'OrderErrors.WrongStatus': 100,
        'OrderErrors.NotSender': 101,
        'OrderErrors.NotCourier': 102,
        'OrderErrors.FeeTooLow': 103,
        'OrderErrors.NotExpired': 104,
        'OrderErrors.DeadlinePassed': 105,
        'OrderErrors.InvalidMessage': 65535,
    }

    readonly address: c.Address
    readonly init: { code: c.Cell, data: c.Cell } | undefined

    protected constructor(address: c.Address, init?: { code: c.Cell, data: c.Cell }) {
        this.address = address;
        this.init = init;
    }

    static fromAddress(address: c.Address) {
        return new Order(address);
    }

    static fromStorage(emptyStorage: {
        sender: c.Address
        courier: c.Address | null
        description: c.Cell
        area: c.Cell
        origin: c.Cell
        reward: coins
        status: OrderStatus
        nonce: uint64
        createdAt: uint32
        acceptedAt: uint32
        extra: CellRef<OrderExtra>
    }, deployedOptions?: DeployedAddrOptions) {
        const initialState = {
            code: deployedOptions?.overrideContractCode ?? Order.CodeCell,
            data: OrderStorage.toCell(OrderStorage.create(emptyStorage)),
        };
        const address = calculateDeployedAddress(initialState.code, initialState.data, deployedOptions ?? {});
        return new Order(address, initialState);
    }

    static createCellOfAcceptOrder(body: {
        courierContact: c.Cell
    }) {
        return AcceptOrder.toCell(AcceptOrder.create(body));
    }

    static createCellOfConfirmDelivery(body: {
    }) {
        return ConfirmDelivery.toCell(ConfirmDelivery.create());
    }

    static createCellOfCancelOrder(body: {
    }) {
        return CancelOrder.toCell(CancelOrder.create());
    }

    static createCellOfClaimExpired(body: {
    }) {
        return ClaimExpired.toCell(ClaimExpired.create());
    }

    static createCellOfCourierRelease(body: {
    }) {
        return CourierRelease.toCell(CourierRelease.create());
    }

    async sendDeploy(provider: ContractProvider, via: Sender, msgValue: coins, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: c.Cell.EMPTY,
            ...extraOptions
        });
    }

    async sendAcceptOrder(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        courierContact: c.Cell
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: AcceptOrder.toCell(AcceptOrder.create(body)),
            ...extraOptions
        });
    }

    async sendConfirmDelivery(provider: ContractProvider, via: Sender, msgValue: coins, body: {
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: ConfirmDelivery.toCell(ConfirmDelivery.create()),
            ...extraOptions
        });
    }

    async sendCancelOrder(provider: ContractProvider, via: Sender, msgValue: coins, body: {
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: CancelOrder.toCell(CancelOrder.create()),
            ...extraOptions
        });
    }

    async sendClaimExpired(provider: ContractProvider, via: Sender, msgValue: coins, body: {
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: ClaimExpired.toCell(ClaimExpired.create()),
            ...extraOptions
        });
    }

    async sendCourierRelease(provider: ContractProvider, via: Sender, msgValue: coins, body: {
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: CourierRelease.toCell(CourierRelease.create()),
            ...extraOptions
        });
    }

    async getOrderData(provider: ContractProvider): Promise<OrderStorage> {
        const r = StackReader.fromGetMethod(11, await provider.get('orderData', []));
        return ({
            $: 'OrderStorage',
            sender: r.readSlice().loadAddress(),
            courier: r.readNullable<c.Address>(
                (r) => r.readSlice().loadAddress()
            ),
            description: r.readCell(),
            area: r.readCell(),
            origin: r.readCell(),
            reward: r.readBigInt(),
            status: r.readBigInt(),
            nonce: r.readBigInt(),
            createdAt: r.readBigInt(),
            acceptedAt: r.readBigInt(),
            extra: r.readCellRef<OrderExtra>(OrderExtra.fromSlice),
        });
    }

    async getStatus(provider: ContractProvider): Promise<OrderStatus> {
        const r = StackReader.fromGetMethod(1, await provider.get('status', []));
        return r.readBigInt();
    }
}
