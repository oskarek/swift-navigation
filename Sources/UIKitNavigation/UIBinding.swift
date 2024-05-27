/// A property wrapper type that can read and write an observable value.
///
/// Like SwiftUI's `Binding`, but for UIKit and other paradigms.
///
/// Use a binding to create a two-way connection between a property that stores data, and a view
/// that displays and changes the data. A binding connects a property to a source of truth stored
/// somewhere, either from an observable model or directly. This is in contrast to SwiftUI bindings,
/// which always have a source of truth that is stored elsewhere.
///
/// For example, a button that toggles between play and pause can create a binding to a property of
/// its parent view controller using the `UIBinding` property wrapper.
///
/// ```swift
/// class PlayButton: UIControl {
///   @UIBinding var isPlaying: Bool
///
///   init(frame: CGRect = .zero, isPlaying: UIBinding<Bool>) {
///     self._isPlaying = isPlaying
///     super.init(frame: frame)
///
///     // ...
///
///     observe { [weak self] in
///       guard let self else { return }
///       titleLabel.text = self.isPlaying ? "Pause" : "Play"
///     }
///     addAction(
///       UIAction { [weak self] _ in self?.isPlaying.toggle() },
///       for: .touchUpInside
///     )
///   }
///
///   // ...
/// }
/// ```
///
/// The parent view controller declares a property to hold the playing state, again using the
/// `UIBinding` property wrapper, but this time with an initial value to indicate that this property
/// is the value's source of truth.
///
/// ```swift
/// final class PlayerViewController: UIViewController {
///   private var episode: Episode
///   @UIBinding private var isPlaying: Bool = false
///
///   // ...
///
///   func viewDidLoad() {
///     super.viewDidLoad()
///
///     let playButton = PlayButton(isPlaying: $isPlaying)
///     let episodeTitleLabel = UILabel()
///
///     // Configure and add subviews...
///
///     observe { [weak self] in
///       guard let self else { return
///       nowPlayingLabel.textColor = isPlaying ? .label : .secondaryLabel
///     }
///   }
///
///   // ...
/// }
/// ```
///
/// When `PlayerViewController` initializes `PlayButton`, it passes a binding of its `isPlaying`
/// state along. Applying the `$` prefix to a property wrapped value returns its ``projectedValue``,
/// which returns a binding to the value.
///
/// Whenever the user taps the `PlayButton`, the `PlayerViewController`` updates its `isPlaying`
/// state.
///
/// > Note: To create bindings to properties of a type that conforms to the `Observable` or
/// > `Perceptible`protocols, use the ``UIBindable`` property wrapper.
@dynamicMemberLookup
@propertyWrapper
@MainActor
public struct UIBinding<Value>: Sendable {
  private let location: any _UIBinding<Value>

  /// The binding's transaction.
  ///
  /// The transaction captures the information needed to update the view when the binding value
  /// changes.
  public var transaction = UITransaction()

  init(location: any _UIBinding<Value>, transaction: UITransaction) {
    self.location = location
    self.transaction = transaction
  }

  init<Root: AnyObject>(
    root: Root,
    keyPath: ReferenceWritableKeyPath<Root, Value>,
    transaction: UITransaction
  ) {
    self.init(
      location: _UIBindingAppendKeyPath(
        base: _UIBindingRoot(wrappedValue: root),
        keyPath: keyPath
      ),
      transaction: transaction
    )
  }

  /// Creates a binding that stores an initial wrapped value.
  ///
  /// You don't call this initializer directly. Instead, Swift calls it for you when you declare a
  /// property with the `@UIBinding` attribute and provide an initial value:
  ///
  /// ```swift
  /// final class MyViewController: UIViewController {
  ///   @UIBinding private var isPlaying: Bool = false
  ///   // ...
  /// }
  /// ```
  /// > Note: SwiftUI's `Binding` type has no such initializer because a view is reinitialized many,
  /// > many times in an application as its parent's body is recomputed, and so Swift has a separate
  /// > `@State` property wrapper that is used to create local, mutable state for a view, and you
  /// > can derive bindings from it.
  /// >
  /// > Reference types like view controllers have no such problem, and can hold onto local, mutable
  /// > state directly. Because of this, it's also totally appropriate to create bindings to these
  /// > properties directly.
  ///
  /// - Parameter wrappedValue: An initial value to store in the state property.
  public init(wrappedValue value: Value) {
    @UIBindable var wrapper = _UIBindingWrapper(value)
    self = $wrapper.value
  }

  /// Creates a binding from the value of another binding.
  ///
  /// You don't call this initializer directly. Instead, Swift calls it for you when you use a
  /// property-wrapper attribute on a binding closure parameter:
  ///
  /// ```swift
  /// present(item: $model.text) { $text in
  ///   EditorViewController(text: $text)
  /// }
  /// ```
  ///
  /// - Parameter projectedValue: A binding.
  public init(projectedValue: UIBinding<Value>) {
    self = projectedValue
  }

  /// Creates a binding with an immutable value.
  ///
  /// Use this method to create a binding to a value that cannot change. This can be useful when
  /// using a `#Preview` to see how a view represents different values.
  ///
  /// ```swift
  /// // Example of binding to an immutable value.
  /// PlayButton(isPlaying: .constant(true))
  /// ```
  ///
  /// - Parameter value: An immutable value.
  /// - Returns: A binding to an immutable value.
  public static func constant(_ value: Value) -> Self {
    Self(location: _UIBindingConstant(value), transaction: UITransaction())
  }

  /// Creates a binding by projecting the base value to an unwrapped value.
  ///
  /// - Parameter base: A value to project to an unwrapped value.
  public init?(_ base: UIBinding<Value?>) {
    guard let initialValue = base.wrappedValue
    else { return nil }
    func open(_ location: some _UIBinding<Value?>) -> any _UIBinding<Value> {
      _UIBindingFromOptional(initialValue: initialValue, base: location)
    }
    self.init(location: open(base.location), transaction: base.transaction)
  }

  /// Creates a binding by projecting the base value to an optional value.
  ///
  /// - Parameter base: A value to project to an optional value.
  public init<V>(_ base: UIBinding<V>) where Value == V? {
    func open(_ location: some _UIBinding<V>) -> any _UIBinding<Value> {
      _UIBindingToOptional(base: location)
    }
    self.init(location: open(base.location), transaction: base.transaction)
  }

  // TODO: How is this used in SwiftUI? Is this useful in UIKit? Remove?
  // public init<V: Hashable>(_ base: UIBinding<V>) where Value == AnyHashable {
  //   func open(_ location: some _UIBinding<V>) -> any _UIBinding<Value> {
  //     _UIBindingToAnyHashable(base: location)
  //   }
  //   self.init(location: open(base.location), transaction: base.transaction)
  // }

  /// The underlying value referenced by the binding variable.
  ///
  /// This property provides primary access to the value's data. However, you don't access
  /// `wrappedValue` directly. Instead, you use the property variable created with the ``UIBinding``
  /// attribute. In the following code example, the binding variable `isPlaying` returns the value
  /// of `wrappedValue`:
  ///
  /// ```swift
  /// class PlayButton: UIControl {
  ///   @UIBinding var isPlaying: Bool
  ///
  ///   init(frame: CGRect = .zero, isPlaying: UIBinding<Bool>) {
  ///     self._isPlaying = isPlaying
  ///     super.init(frame: frame)
  ///
  ///     // ...
  ///
  ///     observe { [weak self] in
  ///       guard let self else { return }
  ///       titleLabel.text = self.isPlaying ? "Pause" : "Play"
  ///     }
  ///     addAction(
  ///       UIAction { [weak self] _ in self?.isPlaying.toggle() },
  ///       for: .touchUpInside
  ///     )
  ///   }
  ///
  ///   // ...
  /// }
  /// ```
  public var wrappedValue: Value {
    get {
      location.wrappedValue
    }
    nonmutating set {
      guard UITransaction.current.isEmpty else {
        location.wrappedValue = newValue
        return
      }
      withUITransaction(transaction) {
        location.wrappedValue = newValue
      }
    }
  }

  /// A projection of the binding value that returns a binding.
  ///
  /// Use the projected value to pass a binding value down a view hierarchy. To get the
  /// `projectedValue`, prefix the property variable with `$`. For example, in the following code
  /// example `PlayerViewController` projects a binding of the property `isPlaying` to the
  /// `PlayButton` view using `$isPlaying`.
  ///
  /// ```swift
  /// final class PlayerViewController: UIViewController {
  ///   private var episode: Episode
  ///   @UIBinding private var isPlaying: Bool = false
  ///
  ///   // ...
  ///
  ///   func viewDidLoad() {
  ///     super.viewDidLoad()
  ///
  ///     let playButton = PlayButton(isPlaying: $isPlaying)
  ///     let episodeTitleLabel = UILabel()
  ///
  ///     // Configure and add subviews...
  ///
  ///     observe { [weak self] in
  ///       guard let self else { return
  ///       nowPlayingLabel.textColor = isPlaying ? .label : .secondaryLabel
  ///     }
  ///   }
  ///
  ///   // ...
  /// }
  /// ```
  public var projectedValue: Self {
    self
  }

  /// Returns a binding to the resulting value of a given key path.
  ///
  /// - Parameter keyPath: A key path to a specific resulting value.
  /// - Returns: A new binding.
  public subscript<Member>(
    dynamicMember keyPath: WritableKeyPath<Value, Member>
  ) -> UIBinding<Member> {
    func open(_ location: some _UIBinding<Value>) -> UIBinding<Member> {
      UIBinding<Member>(
        location: _UIBindingAppendKeyPath(base: location, keyPath: keyPath),
        transaction: transaction
      )
    }
    return open(location)
  }

  /// Returns a binding to the associated value of a given case key path.
  ///
  /// - Parameter keyPath: A case key path to a specific associated value.
  /// - Returns: A new binding.
  public subscript<Member>(
    dynamicMember keyPath: KeyPath<Value.AllCasePaths, AnyCasePath<Value, Member>>
  ) -> UIBinding<Member>?
  where Value: CasePathable {
    func open(_ location: some _UIBinding<Value>) -> UIBinding<Member?> {
      UIBinding<Member?>(
        location: _UIBindingEnumToOptionalCase(base: location, keyPath: keyPath),
        transaction: transaction
      )
    }
    return UIBinding<Member>(open(location))
  }

  /// Returns an optional binding to the associated value of a given case key path.
  ///
  /// - Parameter keyPath: A case key path to a specific associated value.
  /// - Returns: A new binding.
  public subscript<V: CasePathable, Member>(
    dynamicMember keyPath: KeyPath<V.AllCasePaths, AnyCasePath<V, Member>>
  ) -> UIBinding<Member?>
  where Value == V? {
    func open(_ location: some _UIBinding<Value>) -> UIBinding<Member?> {
      UIBinding<Member?>(
        location: _UIBindingOptionalEnumToCase(base: location, keyPath: keyPath),
        transaction: transaction
      )
    }
    return open(location)
  }

  /// Specifies an animation to perform when the binding value changes.
  ///
  /// - Parameter animation: An animation sequence performed when the binding value changes.
  /// - Returns: A new binding.
  public func animation(_ animation: UIAnimation? = .default) -> Self {
    var binding = self
    binding.transaction.animation = animation
    return binding
  }

  /// Specifies a transaction for the binding.
  ///
  /// - Parameter transaction: An instance of a ``UITransaction``.
  /// - Returns: A new binding.
  public func transaction(_ transaction: UITransaction) -> Self {
    var binding = self
    binding.transaction = transaction
    return binding
  }
}

extension UIBinding: Equatable {
  nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
    func openLHS<B: _UIBinding<Value>>(_ lhs: B) -> Bool {
      func openRHS(_ rhs: some _UIBinding<Value>) -> Bool {
        lhs == rhs as? B
      }
      return openRHS(rhs.location)
    }
    return openLHS(lhs.location)
  }
}

extension UIBinding: Hashable {
  nonisolated public func hash(into hasher: inout Hasher) {
    hasher.combine(location)
  }
}

// TODO: Should `UIBinding` be identifiable?
//extension UIBinding: Identifiable {
//  public struct ID: Hashable {
//    private let binding: UIBinding
//  }
//
//  nonisolated public var id: ID {
//    ID(binding: self)
//  }
//}

// TODO: Conform to BidirectionalCollection/Collection/RandomAccessCollection/Sequence?
// TODO: Conform to DynamicProperty?

protocol _UIBinding<Value>: AnyObject, Hashable, Sendable {
  associatedtype Value
  var wrappedValue: Value { get set }
}

private final class _UIBindingRoot<Value: AnyObject>: _UIBinding, @unchecked Sendable {
  var wrappedValue: Value
  init(wrappedValue: Value) {
    self.wrappedValue = wrappedValue
  }
  static func == (lhs: _UIBindingRoot, rhs: _UIBindingRoot) -> Bool {
    lhs.wrappedValue === rhs.wrappedValue
  }
  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(wrappedValue))
  }
}

@Perceptible
private final class _UIBindingWrapper<Value> {
  var value: Value
  init(_ value: Value) {
    self.value = value
  }
}

private final class _UIBindingConstant<Value>: _UIBinding, @unchecked Sendable {
  let value: Value
  init(_ value: Value) {
    self.value = value
  }
  var wrappedValue: Value {
    get { value }
    set {}
  }
  static func == (lhs: _UIBindingConstant, rhs: _UIBindingConstant) -> Bool {
    lhs === rhs
  }
  func hash(into hasher: inout Hasher) {
    if let value = value as? any Hashable {
      hasher.combine(AnyHashable(value))
    } else {
      hasher.combine(ObjectIdentifier(self))
    }
  }
}

private final class _UIBindingAppendKeyPath<Base: _UIBinding, Value>: _UIBinding, @unchecked Sendable {
  let base: Base
  let keyPath: WritableKeyPath<Base.Value, Value>
  init(base: Base, keyPath: WritableKeyPath<Base.Value, Value>) {
    self.base = base
    self.keyPath = keyPath
  }
  var wrappedValue: Value {
    get { base.wrappedValue[keyPath: keyPath] }
    set { base.wrappedValue[keyPath: keyPath] = newValue }
  }
  static func == (lhs: _UIBindingAppendKeyPath, rhs: _UIBindingAppendKeyPath) -> Bool {
    lhs.base == rhs.base && lhs.keyPath == rhs.keyPath
  }
  func hash(into hasher: inout Hasher) {
    hasher.combine(base)
    hasher.combine(keyPath)
  }
}

private final class _UIBindingFromOptional<Base: _UIBinding<Value?>, Value>: _UIBinding, @unchecked Sendable {
  var value: Value
  let base: Base
  init(initialValue: Value, base: Base) {
    self.value = initialValue
    self.base = base
  }
  var wrappedValue: Value {
    get {
      if let value = base.wrappedValue {
        self.value = value
      }
      return value
    }
    set {
      value = newValue
      if base.wrappedValue != nil {
        base.wrappedValue = newValue
      }
    }
  }
  static func == (lhs: _UIBindingFromOptional, rhs: _UIBindingFromOptional) -> Bool {
    lhs.base == rhs.base
  }
  func hash(into hasher: inout Hasher) {
    hasher.combine(base)
  }
}

private final class _UIBindingToOptional<Base: _UIBinding>: _UIBinding {
  let base: Base
  init(base: Base) {
    self.base = base
  }
  var wrappedValue: Base.Value? {
    get {
      base.wrappedValue
    }
    set {
      guard let newValue else { return }
      base.wrappedValue = newValue
    }
  }
  static func == (lhs: _UIBindingToOptional, rhs: _UIBindingToOptional) -> Bool {
    lhs.base == rhs.base
  }
  func hash(into hasher: inout Hasher) {
    hasher.combine(base)
  }
}

//private final class _UIBindingToAnyHashable<Base: _UIBinding>: _UIBinding
//where Base.Value: Hashable {
//  let base: Base
//  init(base: Base) {
//    self.base = base
//  }
//  var wrappedValue: AnyHashable {
//    get { base.wrappedValue }
//    set {
//      // TODO: Use swift-dependencies to make this precondition testable?
//      base.wrappedValue = newValue.base as! Base.Value
//    }
//  }
//  static func == (lhs: _UIBindingToAnyHashable, rhs: _UIBindingToAnyHashable) -> Bool {
//    lhs.base == rhs.base
//  }
//  func hash(into hasher: inout Hasher) {
//    hasher.combine(base)
//  }
//}

private final class _UIBindingEnumToOptionalCase<Base: _UIBinding, Case>: _UIBinding, @unchecked Sendable
where Base.Value: CasePathable {
  let base: Base
  let keyPath: KeyPath<Base.Value.AllCasePaths, AnyCasePath<Base.Value, Case>>
  let casePath: AnyCasePath<Base.Value, Case>
  init(base: Base, keyPath: KeyPath<Base.Value.AllCasePaths, AnyCasePath<Base.Value, Case>>) {
    self.base = base
    self.keyPath = keyPath
    self.casePath = Base.Value.allCasePaths[keyPath: keyPath]
  }
  var wrappedValue: Case? {
    get {
      casePath.extract(from: base.wrappedValue)
    }
    set {
      guard let newValue, casePath.extract(from: base.wrappedValue) != nil
      else { return }
      base.wrappedValue = casePath.embed(newValue)
    }
  }
  static func == (lhs: _UIBindingEnumToOptionalCase, rhs: _UIBindingEnumToOptionalCase) -> Bool {
    lhs.base == rhs.base && lhs.keyPath == rhs.keyPath
  }
  func hash(into hasher: inout Hasher) {
    hasher.combine(base)
    hasher.combine(keyPath)
  }
}

private final class _UIBindingOptionalEnumToCase<
  Base: _UIBinding<Enum?>, Enum: CasePathable, Case
>: _UIBinding, @unchecked Sendable {
  let base: Base
  let keyPath: KeyPath<Enum.AllCasePaths, AnyCasePath<Enum, Case>>
  let casePath: AnyCasePath<Enum, Case>
  init(base: Base, keyPath: KeyPath<Enum.AllCasePaths, AnyCasePath<Enum, Case>>) {
    self.base = base
    self.keyPath = keyPath
    self.casePath = Enum.allCasePaths[keyPath: keyPath]
  }
  var wrappedValue: Case? {
    get {
      base.wrappedValue.flatMap(casePath.extract(from:))
    }
    set {
      guard base.wrappedValue.flatMap(casePath.extract(from:)) != nil
      else { return }
      base.wrappedValue = newValue.map(casePath.embed)
    }
  }
  static func == (lhs: _UIBindingOptionalEnumToCase, rhs: _UIBindingOptionalEnumToCase) -> Bool {
    lhs.base == rhs.base && lhs.keyPath == rhs.keyPath
  }
  func hash(into hasher: inout Hasher) {
    hasher.combine(base)
    hasher.combine(keyPath)
  }
}

extension UIBinding {
  init<V: RandomAccessCollection & RangeReplaceableCollection>(_ base: UIBinding<V>)
  where Value == any RandomAccessCollection & RangeReplaceableCollection {
    func open(_ location: some _UIBinding<V>) -> any _UIBinding<Value> {
      _UIBindingToAnyRangeReplaceableCollection(base: location)
    }
    self.init(location: open(base.location), transaction: base.transaction)
  }
}

private final class _UIBindingToAnyRangeReplaceableCollection<Base: _UIBinding>: _UIBinding
where Base.Value: RandomAccessCollection & RangeReplaceableCollection {
  let base: Base
  init(base: Base) {
    self.base = base
  }
  var wrappedValue: any RandomAccessCollection & RangeReplaceableCollection {
    _read { yield base.wrappedValue }
    _modify {
      var wrappedValue: any RangeReplaceableCollection & RandomAccessCollection = base.wrappedValue
      yield &wrappedValue
      base.wrappedValue = wrappedValue as! Base.Value
    }
  }
  static func == (
    lhs: _UIBindingToAnyRangeReplaceableCollection,
    rhs: _UIBindingToAnyRangeReplaceableCollection
  ) -> Bool {
    lhs.base == rhs.base
  }
  func hash(into hasher: inout Hasher) {
    hasher.combine(base)
  }
}

extension UIBinding {
  init(weak base: UIBinding<Value>) {
    func open(_ location: some _UIBinding<Value>) -> any _UIBinding<Value> {
      _UIBindingToWeak(base: location)
    }
    self.init(location: open(base.location), transaction: base.transaction)
  }
}

private final class _UIBindingToWeak<Base: _UIBinding>: _UIBinding, @unchecked Sendable {
  weak var base: Base?
  let value: Base.Value
  init(base: Base) {
    self.base = base
    self.value = base.wrappedValue
  }
  var wrappedValue: Base.Value {
    get { base?.wrappedValue ?? value }
    set { base?.wrappedValue = newValue }
  }
  static func == (lhs: _UIBindingToWeak, rhs: _UIBindingToWeak) -> Bool {
    lhs.base == rhs.base
  }
  func hash(into hasher: inout Hasher) {
    hasher.combine(base)
  }
}