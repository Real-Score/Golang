package main

import "fmt"

func Add(a, b int) int {
	return a + b
}

func Subtract(a, b int) int {
	return a - b
}

func main() {
	fmt.Println("Demo Go App Running...")
	fmt.Println("2 + 3 =", Add(2, 3))
	fmt.Println("5 - 2 =", Subtract(5, 2))
}
