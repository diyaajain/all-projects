def hanoi_solver(n):
    source = list(range(n, 0, -1))
    auxiliary = []
    target = []

    moves = []

    def record():
        moves.append(f"{source} {auxiliary} {target}")

    record()  # Initial state

    def solve(num_disks, start, end, temp):
        if num_disks == 1:
            end.append(start.pop())
            record()
        else:
            solve(num_disks - 1, start, temp, end)
            end.append(start.pop())
            record()
            solve(num_disks - 1, temp, end, start)

    solve(n, source, target, auxiliary)

    return "\n".join(moves)