package main

import (
	"fmt"
)

type A struct {
	a int
}

func main() {
	queue := make(chan int, 10000000)
	for i := 0; i < 1000000; i++ {
		queue <- i
	}
	done := make(chan bool, 1)
	go func() {
		for i := 0; i < 200000; i++ {
			fmt.Println("g1:")
			<-queue
		}
		done <- true
	}()
	go func() {
		for i := 0; i < 200000; i++ {
			fmt.Println("g2:")
			<-queue
		}
		done <- true
	}()
	go func() {
		for i := 0; i < 200000; i++ {
			fmt.Println("g3:")
			<-queue
		}
		done <- true
	}()
	go func() {
		for i := 0; i < 200000; i++ {
			fmt.Println("g4:")
			<-queue
		}
		done <- true
	}()
	go func() {
		for i := 0; i < 200000; i++ {
			fmt.Println("g5:")
			<-queue
		}
		done <- true
	}()
	for i := 0; i < 5; i++ {
		<-done
		fmt.Println("done")
	}
}
