"""Ch14 Depth limits and query cost analysis - the query cost budget.

Strawberry's ``MaxTokensLimiter`` bounds the document's size; the price of what
it asks for is the example's own: ``first: 50`` asks for fifty of something.
``QueryCostLimiter`` is a schema extension that runs in ``on_execute``, after
parsing and validation and before the first resolver, and prices the selected
operation with the same formula as the Quarkus ``TrackingCostCalculator``:

    cost(field) = 0                                  for ``__*`` fields
    cost(field) = 1 + m * (sum of cost(children))    otherwise

where ``m`` is ``first``, else ``last``, else the default page of 10 on
``cargos`` and ``handlingHistory``; ``len(ids)`` on ``nodes``; and 1 elsewhere.

It runs at execution time rather than as a validation rule because a rule
never sees variable values, so ``first: $n`` could not be priced. The depth and
alias limits are validation rules in this module, installed through
``AddValidationRules``.
"""
from __future__ import annotations

from collections.abc import Iterator
from functools import partial

from graphql import (
    FieldNode,
    FragmentDefinitionNode,
    FragmentSpreadNode,
    GraphQLError,
    GraphQLIncludeDirective,
    GraphQLSkipDirective,
    GraphQLField,
    GraphQLInterfaceType,
    GraphQLNamedType,
    GraphQLObjectType,
    InlineFragmentNode,
    OperationDefinitionNode,
    SelectionSetNode,
    get_named_type,
)
from graphql.execution.values import VariableValues, get_argument_values, get_directive_values, get_variable_values
from graphql.utilities import type_from_ast
from graphql.validation import ValidationContext, ValidationRule
from strawberry.extensions import AddValidationRules, SchemaExtension

DEFAULT_PAGE_SIZE = 10
INT_MAX = 2**31 - 1  # graphql-java sums sibling costs in a 32-bit int
PAGED_FIELDS = frozenset({"cargos", "handlingHistory"})


# Same counts and messages as Strawberry's limiters.
def _fragments(context: ValidationContext) -> dict[str, FragmentDefinitionNode]:
    return {d.name.value: d for d in context.document.definitions if isinstance(d, FragmentDefinitionNode)}


def _alias_rule(max_alias_count: int) -> type[ValidationRule]:
    class MaxAliases(ValidationRule):
        def __init__(self, context: ValidationContext) -> None:
            fragments = _fragments(context)
            memo: dict[str, int] = {}

            def count(selection_set: SelectionSetNode | None) -> int:
                total = 0
                for selection in selection_set.selections if selection_set else ():
                    if isinstance(selection, FieldNode):
                        total += (1 if selection.alias else 0) + count(selection.selection_set)
                    elif isinstance(selection, InlineFragmentNode):
                        total += count(selection.selection_set)
                    elif isinstance(selection, FragmentSpreadNode):
                        name = selection.name.value
                        fragment = fragments.get(name)
                        if fragment is None:
                            continue
                        if name not in memo:
                            memo[name] = 0  # a cycle adds nothing; validation refuses it
                            memo[name] = count(fragment.selection_set)
                        total += memo[name]
                return total

            total = sum(count(d.selection_set) for d in context.document.definitions if isinstance(d, OperationDefinitionNode))
            if total > max_alias_count:
                context.report_error(GraphQLError(f"{total} aliases found. Allowed: {max_alias_count}"))
            super().__init__(context)

    return MaxAliases


def _depth_rule(max_depth: int) -> type[ValidationRule]:
    class MaxDepth(ValidationRule):
        def __init__(self, context: ValidationContext) -> None:
            fragments = _fragments(context)
            memo: dict[str, int] = {}

            def height(selection_set: SelectionSetNode | None) -> int:
                # The deepest field below, a root field being 0 (leaves count).
                deepest = 0
                for selection in selection_set.selections if selection_set else ():
                    if isinstance(selection, FieldNode):
                        if selection.name.value.startswith("__") or not selection.selection_set:
                            continue
                        deepest = max(deepest, 1 + height(selection.selection_set))
                    elif isinstance(selection, InlineFragmentNode):
                        deepest = max(deepest, height(selection.selection_set))
                    elif isinstance(selection, FragmentSpreadNode):
                        name = selection.name.value
                        fragment = fragments.get(name)
                        if fragment is None:
                            continue
                        if name not in memo:
                            memo[name] = 0
                            memo[name] = height(fragment.selection_set)
                        deepest = max(deepest, memo[name])
                return deepest

            operations = {
                (d.name.value if d.name else "anonymous"): d
                for d in context.document.definitions
                if isinstance(d, OperationDefinitionNode)
            }
            for name, operation in operations.items():
                if height(operation.selection_set) > max_depth:
                    context.report_error(
                        GraphQLError(f"'{name}' exceeds maximum operation depth of {max_depth}", [operation])
                    )
            super().__init__(context)

    return MaxDepth


def depth_limiter(max_depth: int) -> AddValidationRules:
    return AddValidationRules([_depth_rule(max_depth)])


def alias_limiter(max_alias_count: int) -> AddValidationRules:
    return AddValidationRules([_alias_rule(max_alias_count)])


class QueryCostLimiter(SchemaExtension):
    def __init__(self, *, max_cost: int, max_tokens: int) -> None:
        self.max_cost = max_cost
        # graphql-java adds a field's siblings in an int, so the Quarkus
        # calculator clamps each field's cost to INT_MAX // max_tokens: a
        # document of at most max_tokens fields then sums to less than 2**31.
        # The clamp is far above the budget, and this stack clamps the same way
        # so that the two report the same total for a document that reaches it.
        self.field_cap = INT_MAX // max_tokens

    def on_execute(self) -> Iterator[None]:
        context = self.execution_context
        document = context.graphql_document
        schema = context.schema._schema  # the graphql-core schema behind the Strawberry one
        operation, fragments = None, {}
        for definition in document.definitions:
            if isinstance(definition, FragmentDefinitionNode):
                fragments[definition.name.value] = definition
            elif isinstance(definition, OperationDefinitionNode) and (
                context.operation_name is None or (definition.name and definition.name.value == context.operation_name)
            ):
                operation = operation or definition
        if operation is not None:
            root = schema.get_root_type(operation.operation)
            variables = get_variable_values(schema, operation.variable_definitions or [], context.variables or {})
            if isinstance(variables, list):  # uncoercible variables: execution reports them, at no cost
                variables = VariableValues({}, {})
            walker = _Walker(schema, fragments, variables, self.field_cap)
            cost = walker.selection_set(root, operation.selection_set)
            if cost > self.max_cost:
                raise GraphQLError(f"maximum query complexity exceeded {cost} > {self.max_cost}")
        yield


class _Walker:
    """Prices a selection set the way graphql-java's analyser does: in document
    order, with each fragment definition counted the first time it is spread and
    not again. A second spread of the same fragment, in this selection set or
    any other, adds nothing; a fragment definition is priced once, as the
    traverser does (see the chapter). A field, inline
    fragment or spread that ``@skip`` or ``@include`` excludes is not walked,
    and a skipped spread does not mark its fragment as counted: graphql-java
    aborts it before it records the visit, and a later live spread of the same
    fragment is priced."""

    def __init__(
        self, schema, fragments: dict[str, FragmentDefinitionNode], variables: VariableValues, field_cap: int
    ) -> None:
        self.schema = schema
        self.fragments = fragments
        self.variables = variables
        self.field_cap = field_cap
        self.spread: set[str] = set()

    def selection_set(self, parent: GraphQLNamedType, selections: SelectionSetNode) -> int:
        total = 0
        for node in selections.selections:
            if not self.included(node):
                continue
            if isinstance(node, FieldNode):
                total += self.field(parent, node)
            elif isinstance(node, InlineFragmentNode):
                condition = type_from_ast(self.schema, node.type_condition) if node.type_condition else parent
                total += self.selection_set(condition, node.selection_set)
            elif isinstance(node, FragmentSpreadNode) and node.name.value not in self.spread:
                self.spread.add(node.name.value)
                fragment = self.fragments[node.name.value]
                condition = type_from_ast(self.schema, fragment.type_condition)
                total += self.selection_set(condition, fragment.selection_set)
        return total

    def included(self, node: FieldNode | InlineFragmentNode | FragmentSpreadNode) -> bool:
        skip = get_directive_values(GraphQLSkipDirective, node, self.variables)
        include = get_directive_values(GraphQLIncludeDirective, node, self.variables)
        return not (skip and skip["if"]) and (include is None or include["if"])

    def field(self, parent: GraphQLNamedType, node: FieldNode) -> int:
        name = node.name.value
        if name.startswith("__"):
            return 0
        definition: GraphQLField | None = (
            parent.fields.get(name) if isinstance(parent, GraphQLObjectType | GraphQLInterfaceType) else None
        )
        if definition is None:
            return 1
        children = 0
        if node.selection_set is not None:
            children = self.selection_set(get_named_type(definition.type), node.selection_set)
        return min(self.field_cap, 1 + self.multiplier(name, definition, node) * children)

    def multiplier(self, name: str, definition: GraphQLField, node: FieldNode) -> int:
        if name not in PAGED_FIELDS and name != "nodes":
            return 1
        arguments = get_argument_values(definition, node, self.variables)
        if name == "nodes":
            ids = arguments.get("ids")
            return len(ids) if isinstance(ids, list) else 1
        for argument in ("first", "last"):
            value = arguments.get(argument)
            if isinstance(value, int) and not isinstance(value, bool):
                return max(0, value)  # a negative page size must not offset the price of another field
        return DEFAULT_PAGE_SIZE
