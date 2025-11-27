"""
Pagination Component for Alarm Dashboard
=========================================

페이지 네비게이션 UI 제공
- 현재 페이지 / 총 페이지
- 이전/다음 버튼
- 페이지 번호 버튼

작성일: 2025-10-02
수정일: 2025-10-23 - Added computed variable support
참고: docs/alarm/alarm-components.md
"""

import reflex as rx


def pagination(
    current_page: int | rx.Var,
    total_pages: int | rx.Var,
    total_items: int | rx.Var,
    page_size: int | rx.Var,
    on_prev: rx.EventHandler,
    on_next: rx.EventHandler,
    on_page_change: rx.EventHandler | None = None,
    page_info: str | rx.Var | None = None,  # NEW: Optional page_info computed var
    has_prev_page: bool | rx.Var | None = None,  # NEW: Optional has_prev_page
    has_next_page: bool | rx.Var | None = None,  # NEW: Optional has_next_page
) -> rx.Component:
    """
    페이지네이션 컴포넌트

    Args:
        current_page: 현재 페이지 (1-indexed)
        total_pages: 총 페이지 수
        total_items: 총 아이템 수
        page_size: 페이지당 아이템 수
        on_prev: 이전 페이지 핸들러
        on_next: 다음 페이지 핸들러
        on_page_change: 특정 페이지로 이동 핸들러
        page_info: (선택) Computed page_info string (예: "1-20 / 144")
        has_prev_page: (선택) Computed has_prev_page boolean
        has_next_page: (선택) Computed has_next_page boolean

    Returns:
        rx.Component: Pagination 컴포넌트

    Examples:
        >>> # Legacy usage (backward compatible)
        >>> pagination(
        ...     current_page=AlarmsState.page,
        ...     total_pages=AlarmsState.total_pages,
        ...     total_items=AlarmsState.filtered_count,
        ...     page_size=AlarmsState.page_size,
        ...     on_prev=AlarmsState.prev_page,
        ...     on_next=AlarmsState.next_page,
        ... )
        >>>
        >>> # New usage (with computed variables)
        >>> pagination(
        ...     current_page=AlarmsState.page,
        ...     total_pages=AlarmsState.total_pages,
        ...     total_items=AlarmsState.filtered_count,
        ...     page_size=AlarmsState.page_size,
        ...     page_info=AlarmsState.page_info,
        ...     has_prev_page=AlarmsState.has_prev_page,
        ...     has_next_page=AlarmsState.has_next_page,
        ...     on_prev=AlarmsState.prev_page,
        ...     on_next=AlarmsState.next_page,
        ... )
    """

    # Use provided page_info or compute it (backward compatibility)
    if page_info is not None:
        display_info = f"Showing {page_info}"
    else:
        display_info = f"Showing {(current_page - 1) * page_size + 1}-{rx.cond(current_page * page_size > total_items, total_items, current_page * page_size)} of {total_items}"

    # Use provided has_prev_page or compute it (backward compatibility)
    if has_prev_page is not None:
        prev_disabled = ~has_prev_page  # Reflex boolean negation
    else:
        prev_disabled = current_page == 1

    # Use provided has_next_page or compute it (backward compatibility)
    if has_next_page is not None:
        next_disabled = ~has_next_page  # Reflex boolean negation
    else:
        next_disabled = current_page >= total_pages

    return rx.hstack(
        # 왼쪽: 항목 정보
        rx.text(
            display_info,
            size="2",
            color="gray",
        ),

        rx.spacer(),

        # 오른쪽: 페이지 버튼
        rx.hstack(
            # Previous 버튼
            rx.icon_button(
                rx.icon("chevron-left"),
                size="1",
                variant="soft",
                disabled=prev_disabled,
                on_click=on_prev,
            ),

            # 페이지 정보
            rx.text(
                f"{current_page} / {total_pages}",
                size="2",
                weight="medium",
            ),

            # Next 버튼
            rx.icon_button(
                rx.icon("chevron-right"),
                size="1",
                variant="soft",
                disabled=next_disabled,
                on_click=on_next,
            ),

            spacing="2",
            align="center",
        ),

        justify="between",
        align="center",
        width="100%",
        padding="3",
        border_top=f"1px solid {rx.color('gray', 3)}",
    )
