# Performance Comparison

Benchmarks comparing Otzel against the [Delta](https://hex.pm/packages/delta) Elixir library.

**Environment:**
- OS: Linux
- CPU: AMD Ryzen 7 7840U
- Cores: 16
- RAM: 30.66 GB
- Elixir: 1.18.4
- Erlang: 28.1
- JIT: enabled

## High-Complexity Benchmarks

Randomized OT operations generated via StreamData, representing highly fragmented documents with many small operations. This stress-tests the OT algorithms.

### Summary

| Operation | Otzel (iomemo) | Delta | Speedup |
|-----------|----------------|-------|---------|
| diff | 526 μs | 676 μs | **1.29x** |
| compose | 33.3 ms | 2,046 ms | **61x** |
| invert | 26.7 ms | 8,849 ms | **331x** |

### Diff

| Implementation | ips | avg | median | memory |
|----------------|-----|-----|--------|--------|
| otzel:binary | 1.90 K | 526 μs | 514 μs | 1.13 MB |
| otzel:binmemo | 1.89 K | 528 μs | 516 μs | 1.12 MB |
| otzel:iomemo | 1.88 K | 533 μs | 520 μs | 1.12 MB |
| delta | 1.48 K | 676 μs | 664 μs | 1.33 MB |

Otzel is **1.29x faster** with **18% less memory**.

### Compose

| Implementation | ips | avg | median | memory |
|----------------|-----|-----|--------|--------|
| otzel:iomemo | 30.04 | 33.3 ms | 33.3 ms | 27.3 MB |
| otzel:binmemo | 16.96 | 59.0 ms | 59.0 ms | 86.7 MB |
| otzel:binary | 9.58 | 104.4 ms | 104.1 ms | 172.5 MB |
| delta | 0.49 | 2,046 ms | 2,079 ms | 541.2 MB |

Otzel (iomemo) is **61x faster** with **20x less memory**.

### Invert

| Implementation | ips | avg | median | memory |
|----------------|-----|-----|--------|--------|
| otzel:iomemo | 37.43 | 26.7 ms | 26.8 ms | 23.5 MB |
| otzel:binmemo | 20.83 | 48.0 ms | 47.8 ms | 75.9 MB |
| otzel:binary | 15.74 | 63.5 ms | 63.3 ms | 76.7 MB |
| delta | 0.11 | 8,849 ms | 8,849 ms | 2,411.9 MB |

Otzel (iomemo) is **331x faster** with **103x less memory**.

## Low-Complexity Benchmarks

### Simple (Single Large Document)

Single ~10KB text block with a small modification. Representative of editing a large document with minimal changes.

#### Summary

| Operation | Otzel (iomemo) | Delta | Speedup |
|-----------|----------------|-------|---------|
| diff | 4.2 μs | 988 μs | **235x** |
| compose | 1.7 μs | 12.2 μs | **7x** |
| invert | 1.9 μs | 14.4 μs | **7.5x** |

#### Diff (Simple)

| Implementation | ips | avg | median | memory |
|----------------|-----|-----|--------|--------|
| otzel:iomemo | 237.33 K | 4.21 μs | 4.13 μs | 6.41 KB |
| otzel:binmemo | 224.42 K | 4.46 μs | 4.38 μs | 6.59 KB |
| otzel:binary | 209.00 K | 4.78 μs | 4.67 μs | 6.59 KB |
| delta | 1.01 K | 988 μs | 975 μs | 1098 KB |

Otzel (iomemo) is **235x faster** with **171x less memory**.

#### Compose (Simple)

| Implementation | ips | avg | median | memory |
|----------------|-----|-----|--------|--------|
| otzel:iomemo | 601.67 K | 1.66 μs | 1.63 μs | 1.41 KB |
| otzel:binmemo | 297.85 K | 3.36 μs | 3.29 μs | 22.09 KB |
| otzel:binary | 72.04 K | 13.88 μs | 13.71 μs | 43.34 KB |
| delta | 81.82 K | 12.22 μs | 12.04 μs | 22.23 KB |

Otzel (iomemo) is **7x faster** with **16x less memory**.

#### Invert (Simple)

| Implementation | ips | avg | median | memory |
|----------------|-----|-----|--------|--------|
| otzel:iomemo | 525.86 K | 1.90 μs | 1.88 μs | 1.66 KB |
| otzel:binmemo | 245.70 K | 4.07 μs | 4.00 μs | 22.34 KB |
| otzel:binary | 59.96 K | 16.68 μs | 16.50 μs | 43.59 KB |
| delta | 69.41 K | 14.41 μs | 14.21 μs | 22.70 KB |

Otzel (iomemo) is **7.5x faster** with **14x less memory**.

### Typing Simulation

Sequential character-by-character edits simulating a user typing. 50 incremental edits for diff, 71 small changes for compose/invert.

#### Summary

| Operation | Otzel (iomemo) | Delta | Speedup |
|-----------|----------------|-------|---------|
| diff | 204 μs | 15.7 ms | **77x** |
| compose | 20.7 μs | 287 μs | **14x** |
| invert | 17.8 μs | 37.9 μs | **2x** |

#### Diff (Typing)

| Implementation | ips | avg | median | memory |
|----------------|-----|-----|--------|--------|
| otzel:iomemo | 4.90 K | 204 μs | 203 μs | 293 KB |
| otzel:binmemo | 4.83 K | 207 μs | 206 μs | 296 KB |
| otzel:binary | 4.62 K | 217 μs | 214 μs | 296 KB |
| delta | 0.064 K | 15.7 ms | 15.6 ms | 18,717 KB |

Otzel (iomemo) is **77x faster** with **64x less memory**.

#### Compose (Typing)

| Implementation | ips | avg | median | memory |
|----------------|-----|-----|--------|--------|
| otzel:iomemo | 48.36 K | 20.68 μs | 20.25 μs | 21.48 KB |
| otzel:binmemo | 30.88 K | 32.38 μs | 31.67 μs | 54.30 KB |
| otzel:binary | 23.82 K | 41.99 μs | 41.17 μs | 73.30 KB |
| delta | 3.49 K | 287 μs | 282 μs | 230 KB |

Otzel (iomemo) is **14x faster** with **11x less memory**.

#### Invert (Typing)

| Implementation | ips | avg | median | memory |
|----------------|-----|-----|--------|--------|
| otzel:iomemo | 56.27 K | 17.77 μs | 17.42 μs | 18.55 KB |
| otzel:binmemo | 31.04 K | 32.22 μs | 31.54 μs | 51.45 KB |
| otzel:binary | 24.38 K | 41.02 μs | 40.17 μs | 70.36 KB |
| delta | 26.41 K | 37.86 μs | 37.21 μs | 38.77 KB |

Otzel (iomemo) is **2x faster** with **2x less memory**.

## String Representation Comparison

Otzel supports multiple string representations:

| Representation | Description | Best For |
|----------------|-------------|----------|
| **iomemo** | IO-list with memoized length | Default, best overall performance |
| **binmemo** | Binary with memoized length | Simpler structure |
| **binary** | Standard Elixir strings | Interop, simplicity |

The `iomemo` representation provides the best performance due to structural sharing during split/concatenate operations common in OT.
