case "${1:-}" in
  -h | --help)
    usage
    ;;
  scale)
    shift
    scale_action "${1:-show}" "${2:-}"
    ;;
  internal)
    shift
    internal_action "${1:-toggle}"
    ;;
  lid)
    shift
    lid_action "${1:-toggle}"
    ;;
  mirror)
    shift
    mirror_action "${1:-toggle}"
    ;;
  brightness)
    shift
    brightness_action "${1:-show}" "${2:-5}"
    ;;
  recover)
    recover_action
    ;;
  wake)
    wake_action
    ;;
  workspace)
    shift
    workspace_action "${1:-}"
    ;;
  workspace-step)
    shift
    workspace_step_action "${1:-next}"
    ;;
  move-window)
    shift
    move_window_action "${1:-}"
    ;;
  workspaces)
    shift
    workspaces_action "${1:-sync}"
    ;;
  list)
    list_action
    ;;
  set)
    shift
    set_action "$@"
    ;;
  try)
    shift
    try_action "${1:-}" "${2:-}" "${3:-}"
    ;;
  keep)
    shift
    keep_action
    ;;
  revert)
    shift
    revert_action
    ;;
  identify)
    shift
    identify_action
    ;;
  status)
    status_action
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    printf 'monitors: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
